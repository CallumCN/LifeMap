import Foundation
import Observation
import OSLog
import MusicKit

/// Plays a recorded song again on the service it came from, starting at a chosen offset.
///
/// Apple Music songs play inside LifeMap through MusicKit's application player, which
/// needs an Apple Music subscription for catalog songs. Spotify songs go through the
/// iOS SDK's App Remote when it is available, since that can launch the Spotify app, and
/// fall back to the Web API otherwise. Either way Spotify Premium is required.
@Observable
@MainActor
final class MusicPlaybackService {
    private(set) var isPlaying = false
    /// The listening event whose song is playing, if any.
    private(set) var currentListenID: UUID?
    private(set) var lastError: String?

    private let spotify: SpotifyNowPlayingProvider
    let appRemote = SpotifyAppRemoteController()
    private var currentSource: MusicSource?
    /// True when the current Spotify playback is being driven through App Remote.
    private var usingAppRemote = false

    init(spotify: SpotifyNowPlayingProvider) {
        self.spotify = spotify
    }

    /// Starts the song from `listen` at `offsetSeconds` into the track.
    func play(_ listen: ListeningEvent, offsetSeconds: Double) async {
        lastError = nil
        SpotifyNowPlayingProvider.log.notice(
            "play source=\(listen.source.rawValue, privacy: .public) track=\(listen.trackID, privacy: .public) title=\(listen.title, privacy: .public) offset=\(Int(offsetSeconds))"
        )
        // Silence whatever we started before switching services.
        if let currentSource, currentSource != listen.source {
            await pause(source: currentSource)
        }
        do {
            switch listen.source {
            case .appleMusic:
                try await playAppleMusic(trackID: listen.trackID, offset: offsetSeconds)
            case .spotify:
                try await playSpotify(trackID: listen.trackID, offset: offsetSeconds)
            case .youtubeMusic:
                throw PlaybackError.unsupported("YouTube Music can't be controlled by other apps.")
            }
            currentSource = listen.source
            currentListenID = listen.id
            isPlaying = true
        } catch {
            SpotifyNowPlayingProvider.log.error("play failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            isPlaying = false
            currentListenID = nil
        }
    }

    /// Moves the playhead of the song this service started.
    func seek(to offsetSeconds: Double) async {
        guard let source = currentSource, isPlaying else { return }
        switch source {
        case .appleMusic:
            ApplicationMusicPlayer.shared.playbackTime = max(0, offsetSeconds)
        case .spotify:
            do {
                if usingAppRemote {
                    try await appRemote.seek(to: offsetSeconds)
                } else {
                    try await spotify.seekPlayback(positionSeconds: offsetSeconds)
                }
            } catch {
                lastError = error.localizedDescription
            }
        case .youtubeMusic:
            break
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
            if usingAppRemote {
                try? await appRemote.pause()
            } else {
                try? await spotify.pausePlayback()
            }
        case .youtubeMusic:
            break
        }
    }

    /// Plays through App Remote where possible, since it can launch the Spotify app.
    /// Falls back to the Web API, which only reaches a device Spotify already considers
    /// awake but can also drive a desktop or speaker.
    private func playSpotify(trackID: String, offset: Double) async throws {
        let log = SpotifyNowPlayingProvider.log
        if SpotifyAppRemoteController.isSDKAvailable, !appRemote.isSpotifyMissing {
            if !appRemote.isConnected {
                let token = try await spotify.currentAccessToken()
                do {
                    try await appRemote.connect(accessToken: token)
                } catch {
                    log.notice("App Remote connect failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if appRemote.isConnected {
                log.notice("Playing via App Remote")
                try await appRemote.play(trackID: trackID, positionSeconds: offset)
                usingAppRemote = true
                return
            }
            // Spotify isn't running. Launching it starts the track there and hands control
            // back to LifeMap, after which later commands go over the connection.
            if appRemote.wake(playing: trackID) {
                log.notice("Launching Spotify to play the track")
                usingAppRemote = true
                return
            }
            log.notice("App Remote unavailable; falling back to the Web API")
        } else {
            log.notice("App Remote not usable (sdk=\(SpotifyAppRemoteController.isSDKAvailable), missing=\(self.appRemote.isSpotifyMissing))")
        }
        try await spotify.startPlayback(trackID: trackID, positionSeconds: offset)
        usingAppRemote = false
    }

    private func playAppleMusic(trackID: String, offset: Double) async throws {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw PlaybackError.unsupported("Connect Apple Music in Settings first.")
        }
        SpotifyNowPlayingProvider.log.notice("Looking up Apple Music catalog song \(trackID, privacy: .public)")
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
