import Foundation
import Observation
import MusicKit

/// Reads the system Music app's playback state through MusicKit.
///
/// `SystemMusicPlayer` mirrors whatever the Music app is playing, so this works for
/// Apple Music streaming and for the user's local library without a developer token.
@Observable
final class AppleMusicNowPlayingProvider: NowPlayingProvider {
    let source: MusicSource = .appleMusic
    private(set) var connectionState: NowPlayingConnectionState = .notConnected

    init() {
        refreshConnectionState()
    }

    func refreshConnectionState() {
        #if os(iOS)
        switch MusicAuthorization.currentStatus {
        case .authorized:
            connectionState = .connected
        case .denied, .restricted:
            connectionState = .unavailable(reason: "Media & Apple Music access was denied in Settings.")
        case .notDetermined:
            connectionState = .notConnected
        @unknown default:
            connectionState = .notConnected
        }
        #else
        connectionState = .unavailable(reason: "The system music player is only available on iOS.")
        #endif
    }

    func connect() async throws {
        #if os(iOS)
        connectionState = .connecting
        let status = await MusicAuthorization.request()
        if status == .authorized {
            connectionState = .connected
        } else {
            connectionState = .unavailable(reason: "Media & Apple Music access was not granted.")
        }
        #endif
    }

    func disconnect() {
        // MusicKit authorization is managed by the system; nothing to revoke locally.
        refreshConnectionState()
    }

    func currentlyPlaying() async throws -> NowPlayingSnapshot? {
        #if os(iOS)
        guard connectionState.isConnected else { return nil }
        let player = SystemMusicPlayer.shared
        guard let entry = player.queue.currentEntry else { return nil }

        let status = player.state.playbackStatus
        let isPlaying = status == .playing || status == .seekingForward || status == .seekingBackward
        let position = player.playbackTime
        let positionSeconds = position.isFinite ? position : nil

        var title = entry.title
        var artist = entry.subtitle ?? ""
        var album: String?
        var duration: Double?
        var trackID = entry.id
        var artworkURL = entry.artwork?.url(width: 300, height: 300)

        switch entry.item {
        case .song(let song):
            title = song.title
            artist = song.artistName
            album = song.albumTitle
            duration = song.duration
            trackID = song.id.rawValue
            artworkURL = song.artwork?.url(width: 300, height: 300) ?? artworkURL
        case .musicVideo(let video):
            title = video.title
            artist = video.artistName
            album = video.albumTitle
            duration = video.duration
            trackID = video.id.rawValue
            artworkURL = video.artwork?.url(width: 300, height: 300) ?? artworkURL
        default:
            break
        }

        return NowPlayingSnapshot(
            source: .appleMusic,
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL,
            durationSeconds: duration,
            positionSeconds: positionSeconds,
            isPlaying: isPlaying,
            observedAt: .now
        )
        #else
        return nil
        #endif
    }
}
