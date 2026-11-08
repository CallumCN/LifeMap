import Foundation

/// Filter shared by the trip list and the map. A trip passes when at least one of
/// its listening events matches the song query, the fraction range, and the sources.
struct TripFilter: Equatable {
    var songQuery: String = ""
    var minFraction: Double = 0
    var maxFraction: Double = 1
    var sources: Set<MusicSource> = Set(MusicSource.allCases)

    var isDefault: Bool {
        songQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && minFraction <= 0
            && maxFraction >= 1
            && sources.count == MusicSource.allCases.count
    }

    func matches(_ listen: ListeningEvent) -> Bool {
        sources.contains(listen.source)
            && listen.fractionListened >= minFraction
            && listen.fractionListened <= maxFraction
            && listen.matches(query: songQuery)
    }

    func matchingListens(in trip: Trip) -> [ListeningEvent] {
        trip.orderedListens.filter(matches)
    }

    func matches(_ trip: Trip) -> Bool {
        if isDefault { return true }
        return trip.listens.contains(where: matches)
    }

    func apply(to trips: [Trip]) -> [Trip] {
        trips.filter(matches)
    }
}
