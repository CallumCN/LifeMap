import Foundation
import SwiftData
import CoreLocation

/// One recorded journey: a path of track points plus the songs heard along the way.
@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var triggerRaw: String
    var activityRaw: String?
    var distanceMeters: Double
    var pointCount: Int

    @Relationship(deleteRule: .cascade, inverse: \TrackPoint.trip)
    var points: [TrackPoint]

    @Relationship(deleteRule: .cascade, inverse: \ListeningEvent.trip)
    var listens: [ListeningEvent]

    init(startDate: Date = .now, trigger: TrackingTrigger, activity: MotionActivityKind? = nil) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = nil
        self.triggerRaw = trigger.rawValue
        self.activityRaw = activity?.rawValue
        self.distanceMeters = 0
        self.pointCount = 0
        self.points = []
        self.listens = []
    }

    var trigger: TrackingTrigger {
        get { TrackingTrigger(rawValue: triggerRaw) ?? .manual }
        set { triggerRaw = newValue.rawValue }
    }

    var activity: MotionActivityKind? {
        get { activityRaw.flatMap(MotionActivityKind.init(rawValue:)) }
        set { activityRaw = newValue?.rawValue }
    }

    var isActive: Bool { endDate == nil }

    var duration: TimeInterval {
        (endDate ?? .now).timeIntervalSince(startDate)
    }

    /// Track points in chronological order.
    var orderedPoints: [TrackPoint] {
        points.sorted { $0.timestamp < $1.timestamp }
    }

    /// Listening events in chronological order.
    var orderedListens: [ListeningEvent] {
        listens.sorted { $0.startedAt < $1.startedAt }
    }

    var coordinates: [CLLocationCoordinate2D] {
        orderedPoints.map(\.coordinate)
    }

    /// The track point closest in time to the given date, used to place songs on the map.
    func nearestPoint(to date: Date) -> TrackPoint? {
        points.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
    }
}
