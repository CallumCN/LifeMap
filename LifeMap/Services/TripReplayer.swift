import Foundation
import CoreLocation
import Observation

/// Replays a finished trip in real time: a position that moves along the route at the
/// recorded pace, with the song that was playing at each moment started on its service.
@Observable
final class TripReplayer {
    private(set) var isPlaying = false
    /// The moment of the trip currently being replayed, or `nil` when idle.
    private(set) var currentDate: Date?
    private(set) var currentCoordinate: CLLocationCoordinate2D?
    private(set) var currentListen: ListeningEvent?

    private let trip: Trip
    private let playback: MusicPlaybackService
    private let points: [TrackPoint]
    private let listens: [ListeningEvent]
    private var task: Task<Void, Never>?

    private static let tick: Duration = .milliseconds(250)

    init(trip: Trip, playback: MusicPlaybackService) {
        self.trip = trip
        self.playback = playback
        self.points = trip.orderedPoints
        self.listens = trip.orderedListens
    }

    var canReplay: Bool {
        points.count > 1
    }

    private var endDate: Date {
        trip.endDate ?? points.last?.timestamp ?? trip.startDate
    }

    /// Starts, or resumes, from `date`. Pass `nil` to resume where it paused or begin at the start.
    func play(from date: Date? = nil) {
        task?.cancel()
        let start = date ?? currentDate ?? trip.startDate
        currentDate = start
        update(to: start)
        isPlaying = true

        task = Task { [weak self] in
            var lastTick = Date()
            var playingListenID: UUID? = UUID()  // Sentinel so the first song always starts.
            while let self, !Task.isCancelled {
                let now = Date()
                let elapsed = now.timeIntervalSince(lastTick)
                lastTick = now

                guard let position = self.currentDate?.addingTimeInterval(elapsed) else { break }
                if position >= self.endDate {
                    self.finish()
                    break
                }
                self.update(to: position)

                if self.currentListen?.id != playingListenID {
                    playingListenID = self.currentListen?.id
                    await self.startMusic(for: self.currentListen, at: position)
                }
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    /// Jumps to the moment a song began and plays from there.
    func play(from listen: ListeningEvent) {
        play(from: listen.startedAt)
    }

    /// Pauses, keeping the current position so `play()` resumes.
    func stop() {
        task?.cancel()
        task = nil
        isPlaying = false
        Task { await playback.stop() }
    }

    private func finish() {
        task = nil
        isPlaying = false
        currentDate = nil
        currentCoordinate = nil
        currentListen = nil
        Task { await playback.stop() }
    }

    private func update(to date: Date) {
        currentDate = date
        currentCoordinate = RouteMath.coordinate(at: date, in: points)
        currentListen = listens.first { $0.startedAt <= date && date <= $0.endedAt }
    }

    private func startMusic(for listen: ListeningEvent?, at date: Date) async {
        guard let listen else {
            await playback.stop()
            return
        }
        // The song's position at this moment: where it was first observed plus the time since.
        let observedStart = listen.observedRanges.first?.start ?? 0
        let offset = observedStart + date.timeIntervalSince(listen.startedAt)
        await playback.play(listen, offsetSeconds: max(0, offset))
    }
}
