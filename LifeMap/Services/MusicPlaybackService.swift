import Foundation
import Observation
import MusicKit

/// Plays a recorded song again on the service it came from, starting at a chosen offset.
///
/// Apple Music songs play inside LifeMap through MusicKit's application player, which
/// needs an Apple Music subscription for catalog songs. Spotify songs are started on the
/// user's active Spotify device through the Web API, which needs Spotify Premium and the
/// Spotify app to be open.
@Observable
final class MusicPlaybackService {
    private(set) var isPlaying = false
    /// The listening event whose song is playing, if any.
    private(set) var currentListenID: UUID?
    private(set) var lastError: String?

    private let spotify: SpotifyNowPlayingProvider
    private var currentSource: MusicSource?

    init(spotify: SpotifyNowPlayingProvider) {
        self.spotify = spotify
    }

    /// Starts the song from `listen` at `offsetSeconds` into the track.
    func play(_ listen: ListeningEvent, offsetSeconds: Double) async {
        lastError = nil
        // Silence whatever we started before switching services.
        if let currentSource, currentSource != listen.source {
            await pause(source: currentSource)
        }
        do {
            switch listen.source {
            case .appleMusic:
                try await playAppleMusic(trackID: listen.trackID, offset: offsetSeconds)
            case .spotify:
                try await spotify.startPlayback(trackID: listen.trackID, positionSeconds: offsetSeconds)
            case .youtubeMusic:
                throw PlaybackError.unsupported("YouTube Music can't be controlled by other apps.")
            }
            currentSource = listen.source
            currentListenID = listen.id
            isPlaying = true
        } catch {
            lastError = error.localizedDescription
            isPlaying = false
            currentListenID = nil
        }
    }

    /// Pauses whatever this service started.
    func stop() async {
        guard let source = currentSource else { return }
        await pause(source: source)
        currentSource = nil
        currentListenID = nil
        isPlaying = false
    }

    private func pause(source: MusicSource) async {
        switch source {
        case .appleMusic:
            ApplicationMusicPlayer.shared.pause()
        case .spotify:
            try? await spotify.pausePlayback()
        case .youtubeMusic:
            break
        }
    }

    private func playAppleMusic(trackID: String, offset: Double) async throws {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw PlaybackError.unsupported("Connect Apple Music in Settings first.")
        }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(trackID))
        let response = try await request.response()
        guard let song = response.items.first else {
            throw PlaybackError.unsupported("This song isn't in the Apple Music catalog, so it can't be replayed.")
        }
        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: [song])
        try await player.prepareToPlay()
        player.playbackTime = max(0, offset)
        try await player.play()
    }

    enum PlaybackError: LocalizedError {
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let reason): reason
            }
        }
    }
}
