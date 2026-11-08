import Foundation

/// Whether the Map tab ranks individual songs or whole artists.
enum RankingKind: String, CaseIterable, Identifiable {
    case songs
    case artists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs: "Songs"
        case .artists: "Artists"
        }
    }
}

/// A song or artist with the total time it was heard across the trips being shown.
struct RankedEntry: Identifiable {
    let id: String
    let kind: RankingKind
    let title: String
    let subtitle: String
    let seconds: Double
    let source: MusicSource?
    /// The play to start when the user taps Play: the song itself, or an artist's most-heard song.
    let topListen: ListeningEvent

    /// Whether a play belongs to this song or artist.
    func matches(_ listen: ListeningEvent) -> Bool {
        switch kind {
        case .songs: Self.songKey(listen) == id
        case .artists: Self.artistKey(listen) == id
        }
    }

    static func songKey(_ listen: ListeningEvent) -> String {
        "song|\(listen.source.rawValue)|\(listen.trackID)"
    }

    static func artistKey(_ listen: ListeningEvent) -> String {
        "artist|\(listen.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    /// Groups plays by song or artist and orders them by total time listened, longest first.
    static func rank(_ listens: [ListeningEvent], by kind: RankingKind) -> [RankedEntry] {
        switch kind {
        case .songs:
            return Dictionary(grouping: listens) { songKey($0) }.map { key, plays in
                let total = plays.reduce(0) { $0 + $1.listenedSeconds }
                let top = plays.max { $0.listenedSeconds < $1.listenedSeconds } ?? plays[0]
                return RankedEntry(id: key, kind: .songs, title: top.title, subtitle: top.artist, seconds: total, source: top.source, topListen: top)
            }
            .sorted { $0.seconds > $1.seconds }

        case .artists:
            return Dictionary(grouping: listens) { artistKey($0) }.map { key, plays in
                let total = plays.reduce(0) { $0 + $1.listenedSeconds }
                let perSong = Dictionary(grouping: plays) { songKey($0) }
                    .mapValues { $0.reduce(0) { $0 + $1.listenedSeconds } }
                let topSongKey = perSong.max { $0.value < $1.value }?.key
                let top = plays.first { songKey($0) == topSongKey } ?? plays[0]
                let subtitle = perSong.count == 1 ? "1 song" : "\(perSong.count) songs"
                return RankedEntry(id: key, kind: .artists, title: top.artist, subtitle: subtitle, seconds: total, source: nil, topListen: top)
            }
            .sorted { $0.seconds > $1.seconds }
        }
    }
}
