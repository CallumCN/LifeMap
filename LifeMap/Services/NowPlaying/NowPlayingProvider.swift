import Foundation

/// A point-in-time view of what a music service is playing.
struct NowPlayingSnapshot: Equatable, Sendable {
    var source: MusicSource
    var trackID: String
    var title: String
    var artist: String
    var album: String?
    var artworkURL: URL?
    /// Full length of the track in seconds, if known.
    var durationSeconds: Double?
    /// Playhead position in seconds, if known.
    var positionSeconds: Double?
    var isPlaying: Bool
    var observedAt: Date

    /// Two snapshots describe the same play when the source and track match.
    func isSameTrack(as other: NowPlayingSnapshot) -> Bool {
        source == other.source && trackID == other.trackID
    }
}

/// How connected a music source currently is.
enum NowPlayingConnectionState: Equatable, Sendable {
    case notConnected
    case connecting
    case connected
    case unavailable(reason: String)

    var isConnected: Bool { self == .connected }
}

/// A music service that can report what is playing right now.
protocol NowPlayingProvider: AnyObject {
    var source: MusicSource { get }
    var connectionState: NowPlayingConnectionState { get }
    /// Request access to the service (MusicKit authorization, OAuth, …).
    func connect() async throws
    func disconnect()
    /// Returns `nil` when nothing is playing or the service is idle.
    func currentlyPlaying() async throws -> NowPlayingSnapshot?
}
