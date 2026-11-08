import Foundation
import CoreLocation
import SwiftData
import Observation

/// Owns the trip currently being recorded and writes track points and plays into SwiftData.
@Observable
final class TripRecorder {
    private(set) var currentTrip: Trip?
    private(set) var lastLocation: CLLocation?
    /// Last time the user was observed moving faster than a slow walk.
    private(set) var lastMovementAt: Date?

    private let modelContext: ModelContext
    private var unsavedPoints = 0

    /// Minimum horizontal movement before a new point is stored.
    private static let minimumDisplacement: CLLocationDistance = 3
    /// Below this speed (m/s) the user is treated as stationary.
    private static let movingSpeedThreshold: CLLocationSpeed = 0.7

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        closeAbandonedTrips()
    }

    var isRecording: Bool { currentTrip != nil }

    func start(trigger: TrackingTrigger, activity: MotionActivityKind?) {
        guard currentTrip == nil else { return }
        let trip = Trip(trigger: trigger, activity: activity)
        modelContext.insert(trip)
        currentTrip = trip
        lastMovementAt = .now
        save()
    }

    func end() {
        guard let trip = currentTrip else { return }
        trip.endDate = .now
        currentTrip = nil
        // Drop trips with nothing in them so the list stays meaningful.
        if trip.pointCount < 2 && trip.listens.isEmpty {
            modelContext.delete(trip)
        }
        save()
        lastLocation = nil
    }

    func updateActivity(_ activity: MotionActivityKind?) {
        guard let trip = currentTrip, let activity, trip.activity == nil else { return }
        trip.activity = activity
    }

    func add(_ location: CLLocation) {
        guard let trip = currentTrip else {
            lastLocation = location
            return
        }
        if location.speed >= Self.movingSpeedThreshold {
            lastMovementAt = location.timestamp
        }
        if let previous = lastLocation {
            let distance = location.distance(from: previous)
            if distance < Self.minimumDisplacement {
                return
            }
            if distance >= Self.movingSpeedThreshold * max(1, location.timestamp.timeIntervalSince(previous.timestamp)) {
                lastMovementAt = location.timestamp
            }
            trip.distanceMeters += distance
        }
        let point = TrackPoint(location: location)
        point.trip = trip
        modelContext.insert(point)
        trip.pointCount += 1
        lastLocation = location
        unsavedPoints += 1
        if unsavedPoints >= 20 {
            save()
        }
    }

    func add(_ listen: CompletedListen) {
        guard let trip = currentTrip else { return }
        let event = ListeningEvent(
            trackID: listen.snapshot.trackID,
            title: listen.snapshot.title,
            artist: listen.snapshot.artist,
            album: listen.snapshot.album,
            artworkURL: listen.snapshot.artworkURL,
            source: listen.snapshot.source,
            startedAt: listen.startedAt,
            endedAt: listen.endedAt,
            durationSeconds: listen.snapshot.durationSeconds ?? listen.listenedSeconds,
            listenedSeconds: listen.listenedSeconds,
            startLocation: listen.startLocation ?? lastLocation,
            endLocation: listen.endLocation ?? lastLocation
        )
        event.trip = trip
        modelContext.insert(event)
        save()
    }

    /// Attaches history imported from a service's "recently played" API to whichever
    /// trip was in progress at the time, placing it on the nearest recorded point.
    func importHistory(_ plays: [SpotifyNowPlayingProvider.RecentPlay]) -> Int {
        var inserted = 0
        for play in plays {
            let startedAt = play.endedAt.addingTimeInterval(-play.durationSeconds)
            guard let trip = trip(containing: startedAt, or: play.endedAt) else { continue }
            let alreadyLogged = trip.listens.contains {
                $0.trackID == play.trackID && abs($0.endedAt.timeIntervalSince(play.endedAt)) < 120
            }
            if alreadyLogged { continue }
            let event = ListeningEvent(
                trackID: play.trackID,
                title: play.title,
                artist: play.artist,
                album: play.album,
                artworkURL: play.artworkURL,
                source: .spotify,
                startedAt: startedAt,
                endedAt: play.endedAt,
                durationSeconds: play.durationSeconds,
                listenedSeconds: play.durationSeconds,
                isEstimated: true,
                startLocation: trip.nearestPoint(to: startedAt)?.location,
                endLocation: trip.nearestPoint(to: play.endedAt)?.location
            )
            event.trip = trip
            modelContext.insert(event)
            inserted += 1
        }
        if inserted > 0 { save() }
        return inserted
    }

    private func trip(containing start: Date, or end: Date) -> Trip? {
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { trip in
                trip.startDate <= end && (trip.endDate == nil || trip.endDate! >= start)
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// If the app was killed mid-trip, close that trip at its last point.
    private func closeAbandonedTrips() {
        let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.endDate == nil })
        guard let open = try? modelContext.fetch(descriptor) else { return }
        for trip in open {
            trip.endDate = trip.orderedPoints.last?.timestamp ?? trip.startDate
        }
        if !open.isEmpty { save() }
    }

    func save() {
        unsavedPoints = 0
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save trip data: \(error)")
        }
    }
}
