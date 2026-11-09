import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SpotifyiOS)
import SpotifyiOS
#endif

/// Controls playback through Spotify's iOS SDK (App Remote) rather than the Web API.
///
/// The Web API can only command a device Spotify already considers awake, so replay fails
/// unless the person has opened Spotify recently. App Remote talks to the Spotify app on
/// this device directly and can launch it, so a trip can be replayed from cold.
///
/// The SDK ships as a binary framework and is optional: without it the whole type compiles
/// to stubs that report themselves unavailable, and `MusicPlaybackService` falls back to
/// the Web API. Add it with File > Add Package Dependencies in Xcode, using
/// `https://github.com/spotify/ios-sdk`.
@Observable
@MainActor
final class SpotifyAppRemoteController {
    /// True when the SDK is linked into the app.
    static var isSDKAvailable: Bool {
        #if canImport(SpotifyiOS)
        true
        #else
        false
        #endif
    }

    private(set) var isConnected = false
    private(set) var lastError: String?

    enum AppRemoteError: LocalizedError {
        case sdkMissing
        case spotifyNotInstalled
        case notConnected
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .sdkMissing:
                "Spotify's iOS SDK isn't bundled with this build."
            case .spotifyNotInstalled:
                "Spotify isn't installed on this iPhone."
            case .notConnected:
                "Not connected to the Spotify app."
            case .failed(let reason):
                reason
            }
        }
    }

    /// Set once a connection attempt has reported that Spotify isn't on this device, so
    /// later replays skip straight to the Web API instead of trying again.
    private(set) var isSpotifyMissing = false

    #if canImport(SpotifyiOS)

    private lazy var appRemote: SPTAppRemote = {
        let configuration = SPTConfiguration(
            clientID: AppSettings.spotifyClientID,
            redirectURL: URL(string: AppSettings.spotifyRedirectURI)!
        )
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        remote.delegate = delegateProxy
        return remote
    }()

    private lazy var delegateProxy = AppRemoteDelegateProxy(owner: self)
    /// Resumed once a connection attempt succeeds or fails.
    private var connectionContinuation: CheckedContinuation<Void, Error>?

    /// Connects to the Spotify app, launching it first if it isn't running.
    ///
    /// `accessToken` comes from the same PKCE sign-in the Web API uses and must include
    /// the `app-remote-control` scope.
    func connect(accessToken: String, wakeIfNeeded: Bool = true) async throws {
        guard !isConnected else { return }
        guard !isSpotifyMissing else { throw AppRemoteError.spotifyNotInstalled }
        appRemote.connectionParameters.accessToken = accessToken

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connectionContinuation = continuation
                appRemote.connect()
            }
        } catch {
            // Spotify is installed but asleep: `wake` launches it, which also connects.
            guard wakeIfNeeded else { throw error }
            try await wake()
        }
    }

    /// Brings the Spotify app to the foreground so it can accept a connection. Control
    /// returns to LifeMap through the redirect URL once Spotify has started.
    private func wake() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectionContinuation = continuation
            appRemote.authorizeAndPlayURI("") { installed in
                guard !installed else { return }
                Task { @MainActor in
                    self.isSpotifyMissing = true
                    self.finishConnecting(with: AppRemoteError.spotifyNotInstalled)
                }
            }
        }
    }

    /// Hands back the parameters Spotify returns on the redirect URL after waking.
    func handleCallback(url: URL) {
        let parameters = appRemote.authorizationParameters(from: url)
        if let token = parameters?[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
        } else if let error = parameters?[SPTAppRemoteErrorDescriptionKey] {
            finishConnecting(with: AppRemoteError.failed(error))
        }
    }

    /// Reconnects after returning from the background, where iOS drops the connection.
    func reconnectIfNeeded() {
        guard !isConnected, appRemote.connectionParameters.accessToken != nil else { return }
        appRemote.connect()
    }

    func disconnect() {
        guard isConnected else { return }
        appRemote.disconnect()
    }

    func play(trackID: String, positionSeconds: Double) async throws {
        try await perform { playerAPI, done in
            playerAPI.play("spotify:track:\(trackID)", callback: done)
        }
        if positionSeconds >= 1 {
            try await seek(to: positionSeconds)
        }
    }

    func seek(to positionSeconds: Double) async throws {
        let milliseconds = Int(max(0, positionSeconds) * 1000)
        try await perform { playerAPI, done in
            playerAPI.seek(toPosition: milliseconds, callback: done)
        }
    }

    func pause() async throws {
        try await perform { playerAPI, done in
            playerAPI.pause(callback: done)
        }
    }

    /// Runs one player command and waits for Spotify's acknowledgement.
    private func perform(_ command: @escaping (SPTAppRemotePlayerAPI, @escaping SPTAppRemoteCallback) -> Void) async throws {
        guard isConnected, let playerAPI = appRemote.playerAPI else {
            throw AppRemoteError.notConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            command(playerAPI) { _, error in
                if let error {
                    continuation.resume(throwing: AppRemoteError.failed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Connection callbacks

    fileprivate func didConnect() {
        isConnected = true
        lastError = nil
        finishConnecting(with: nil)
    }

    fileprivate func didDisconnect(error: Error?) {
        isConnected = false
        if let error { lastError = error.localizedDescription }
        finishConnecting(with: error.map { AppRemoteError.failed($0.localizedDescription) })
    }

    private func finishConnecting(with error: Error?) {
        guard let continuation = connectionContinuation else { return }
        connectionContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    #else

    // MARK: - Stubs used when the SDK isn't linked

    func connect(accessToken: String, wakeIfNeeded: Bool = true) async throws {
        throw AppRemoteError.sdkMissing
    }

    func handleCallback(url: URL) {}
    func reconnectIfNeeded() {}
    func disconnect() {}

    func play(trackID: String, positionSeconds: Double) async throws {
        throw AppRemoteError.sdkMissing
    }

    func seek(to positionSeconds: Double) async throws {
        throw AppRemoteError.sdkMissing
    }

    func pause() async throws {
        throw AppRemoteError.sdkMissing
    }

    #endif
}

#if canImport(SpotifyiOS)
/// Bridges the SDK's Objective-C delegate onto the main actor.
private final class AppRemoteDelegateProxy: NSObject, SPTAppRemoteDelegate {
    private weak var owner: SpotifyAppRemoteController?

    init(owner: SpotifyAppRemoteController) {
        self.owner = owner
        super.init()
    }

    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in owner?.didConnect() }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: (any Error)?) {
        Task { @MainActor in owner?.didDisconnect(error: error) }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: (any Error)?) {
        Task { @MainActor in owner?.didDisconnect(error: error) }
    }
}
#endif
