import Foundation
import CoreLocation

/// A run of consecutive track points during which one song, or nothing, was playing.
struct RouteSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let listen: ListeningEvent?
}

extension Trip {
    /// The song playing at a moment of the trip, if any.
    func listen(at date: Date) -> ListeningEvent? {
        orderedListens.first { $0.startedAt <= date && date <= $0.endedAt }
    }

    /// The route split wherever the playing song changes. Each segment starts with the
    /// previous segment's last point so the drawn line has no gaps.
    func routeSegments() -> [RouteSegment] {
        let listens = orderedListens
        var segments: [RouteSegment] = []
        var current: [CLLocationCoordinate2D] = []
        var currentListen: ListeningEvent?

        for point in orderedPoints {
            let listen = listens.first { $0.startedAt <= point.timestamp && point.timestamp <= $0.endedAt }
            if !current.isEmpty, listen?.id != currentListen?.id {
                segments.append(RouteSegment(id: segments.count, coordinates: current, listen: currentListen))
                current = [current[current.count - 1]]
            }
            currentListen = listen
            current.append(point.coordinate)
        }
        if !current.isEmpty {
            segments.append(RouteSegment(id: segments.count, coordinates: current, listen: currentListen))
        }
        return segments
    }

    /// Where the user was at a moment of the trip, interpolated between recorded points.
    func coordinate(at date: Date) -> CLLocationCoordinate2D? {
        RouteMath.coordinate(at: date, in: orderedPoints)
    }
}

enum RouteMath {
    /// Interpolates a position along chronologically ordered track points.
    static func coordinate(at date: Date, in points: [TrackPoint]) -> CLLocationCoordinate2D? {
        guard let first = points.first, let last = points.last else { return nil }
        if date <= first.timestamp { return first.coordinate }
        if date >= last.timestamp { return last.coordinate }

        // Binary search for the first point at or after `date`.
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timestamp < date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let after = points[low]
        let before = points[max(0, low - 1)]
        let span = after.timestamp.timeIntervalSince(before.timestamp)
        guard span > 0 else { return after.coordinate }
        let fraction = date.timeIntervalSince(before.timestamp) / span
        return CLLocationCoordinate2D(
            latitude: before.latitude + (after.latitude - before.latitude) * fraction,
            longitude: before.longitude + (after.longitude - before.longitude) * fraction
        )
    }
}
