import Foundation
import Observation

/// Placeholder for YouTube Music.
///
/// Google does not offer a public API for YouTube Music playback state or listening
/// history, and iOS does not let third-party apps read another app's Now Playing
/// information. Until that changes, this provider reports itself as unavailable so the
/// UI can explain the limitation. Swap in a real implementation here if you host your
/// own bridge (for example, a YouTube Data API `watch history` export importer).
@Observable
final class YouTubeMusicNowPlayingProvider: NowPlayingProvider {
    let source: MusicSource = .youtubeMusic
    private(set) var connectionState: NowPlayingConnectionState = .unavailable(
        reason: "YouTube Music has no public now-playing or history API. You can still log trips, and import a Google Takeout history export later."
    )

    func connect() async throws {
        // Intentionally no-op; see the type documentation.
    }

    func disconnect() {}

    func currentlyPlaying() async throws -> NowPlayingSnapshot? {
        nil
    }
}
