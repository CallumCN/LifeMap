import Foundation
import SwiftData
import CoreLocation

/// A stretch of a track that was observed playing, in seconds from the start of the track.
struct PlayedRange: Codable, Hashable, Sendable {
    var start: Double
    var end: Double

    var length: Double { max(0, end - start) }
}

extension Array where Element == PlayedRange {
    /// Ranges sorted by start, with overlapping or touching ones combined.
    func merged() -> [PlayedRange] {
        var result: [PlayedRange] = []
        for range in sorted(by: { $0.start < $1.start }) {
            if let last = result.last, range.start <= last.end {
                result[result.count - 1].end = Swift.max(last.end, range.end)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Total seconds covered, counting overlaps once.
    var coveredSeconds: Double {
        merged().reduce(0) { $0 + $1.length }
    }
}

/// One play of a song, with how much of it was heard and where it started and ended.
@Model
final class ListeningEvent {
    @Attribute(.unique) var id: UUID
    var trackID: String
    var title: String
    var artist: String
    var album: String?
    var artworkURLString: String?
    var sourceRaw: String
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Double
    var listenedSeconds: Double
    /// Stored (not computed) so it can be used in queries and sorted cheaply.
    var fractionListened: Double
    /// True when the play was imported from a history API that doesn't report how much was heard.
    var isEstimated: Bool
    /// Stretches of the track observed playing. `nil` for plays recorded before this was
    /// tracked and for imported history, which only knows that the song was played.
    var playedRanges: [PlayedRange]?
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var trip: Trip?

    init(
        trackID: String,
        title: String,
        artist: String,
        album: String?,
        artworkURL: URL?,
        source: MusicSource,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Double,
        listenedSeconds: Double,
        playedRanges: [PlayedRange] = [],
        isEstimated: Bool = false,
        startLocation: CLLocation?,
        endLocation: CLLocation?
    ) {
        self.id = UUID()
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURLString = artworkURL?.absoluteString
        self.sourceRaw = source.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.listenedSeconds = listenedSeconds
        self.fractionListened = ListeningEvent.fraction(listened: listenedSeconds, duration: durationSeconds)
        self.isEstimated = isEstimated
        self.playedRanges = playedRanges.isEmpty ? nil : playedRanges.merged()
        self.startLatitude = startLocation?.coordinate.latitude
        self.startLongitude = startLocation?.coordinate.longitude
        self.endLatitude = endLocation?.coordinate.latitude
        self.endLongitude = endLocation?.coordinate.longitude
    }

    static func fraction(listened: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, listened / duration))
    }

    /// Observed ranges, or empty when none were recorded.
    var observedRanges: [PlayedRange] {
        playedRanges ?? []
    }

    var source: MusicSource {
        get { MusicSource(rawValue: sourceRaw) ?? .appleMusic }
        set { sourceRaw = newValue.rawValue }
    }

    var artworkURL: URL? {
        artworkURLString.flatMap(URL.init(string:))
    }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let startLatitude, let startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    var endCoordinate: CLLocationCoordinate2D? {
        guard let endLatitude, let endLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: endLatitude, longitude: endLongitude)
    }

    /// Case- and diacritic-insensitive match against title, artist, and album.
    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return title.localizedStandardContains(trimmed)
            || artist.localizedStandardContains(trimmed)
            || (album?.localizedStandardContains(trimmed) ?? false)
    }
}
