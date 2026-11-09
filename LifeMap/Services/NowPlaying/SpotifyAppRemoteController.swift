import Foundation
import Observation
#if canImport(SpotifyiOS)
import SpotifyiOS
#endif

/// Controls playback through Spotify's iOS SDK (App Remote) rather than the Web API.
///
/// The Web API can only command a device Spotify already considers awake, so replay fails
/// unless the person has opened Spotify recently. App Remote talks to the Spotify app on
/// this device directly and can launch it, so a trip can be replayed from cold.
///
/// The SDK is an optional dependency: without it the whole type compiles to stubs that
/// report themselves unavailable, and `MusicPlaybackService` falls back to the Web API.
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
    /// Set once Spotify reports it isn't installed, so later replays skip straight to the
    /// Web API, which can still reach a desktop or speaker.
    private(set) var isSpotifyMissing = false

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

    #if canImport(SpotifyiOS)

    @ObservationIgnored
    private lazy var appRemote: SPTAppRemote = {
        let configuration = SPTConfiguration(
            clientID: AppSettings.spotifyClientID,
            redirectURL: URL(string: AppSettings.spotifyRedirectURI)!
        )
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        remote.delegate = delegateProxy
        return remote
    }()

    @ObservationIgnored
    private lazy var delegateProxy = AppRemoteDelegateProxy(owner: self)

    /// Resumed once a connection attempt succeeds or fails.
    @ObservationIgnored
    private var connectionContinuation: CheckedContinuation<Void, Error>?

    /// Connects to a Spotify app that is already running.
    ///
    /// `accessToken` comes from the same PKCE sign-in the Web API uses and must carry the
    /// `app-remote-control` scope. Throws if Spotify isn't running, in which case the
    /// caller should fall back to `wake(playing:)`.
    func connect(accessToken: String) async throws {
        guard !isConnected else { return }
        guard !isSpotifyMissing else { throw AppRemoteError.spotifyNotInstalled }
        appRemote.connectionParameters.accessToken = accessToken
        try await awaitConnection { [appRemote] in appRemote.connect() }
    }

    /// Launches the Spotify app and starts a track there.
    ///
    /// This is the only way to reach Spotify when it isn't running. It brings Spotify to
    /// the front; iOS returns to LifeMap through the redirect URL, which arrives in
    /// `handleCallback(url:)` and completes the connection for later commands.
    /// Returns false when Spotify isn't installed.
    @discardableResult
    func wake(playing trackID: String?) -> Bool {
        let uri = trackID.map { "spotify:track:\($0)" } ?? ""
        let installed = appRemote.authorizeAndPlayURI(uri)
        if !installed {
            isSpotifyMissing = true
            lastError = AppRemoteError.spotifyNotInstalled.localizedDescription
        }
        return installed
    }

    /// Takes the token Spotify returns on the redirect URL after being launched.
    func handleCallback(url: URL) {
        guard let parameters = appRemote.authorizationParameters(from: url) else { return }
        if let token = parameters[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
        } else if let error = parameters[SPTAppRemoteErrorDescriptionKey] {
            lastError = error
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
            playerAPI.pause(done)
        }
    }

    /// Runs one player command and waits for Spotify's acknowledgement.
    private func perform(_ command: (SPTAppRemotePlayerAPI, @escaping SPTAppRemoteCallback) -> Void) async throws {
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

    /// Starts a connection attempt and waits for a delegate callback, giving up rather
    /// than hanging if Spotify never answers.
    private func awaitConnection(timeout: Duration = .seconds(6), start: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectionContinuation = continuation
            start()
            Task {
                try? await Task.sleep(for: timeout)
                finishConnecting(with: AppRemoteError.failed("Spotify didn't respond."))
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
        finishConnecting(with: error.map { AppRemoteError.failed($0.localizedDescription) }
            ?? AppRemoteError.notConnected)
    }

    /// Resumes a pending connection attempt, if there is one. Safe to call repeatedly.
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

    func connect(accessToken: String) async throws {
        throw AppRemoteError.sdkMissing
    }

    @discardableResult
    func wake(playing trackID: String?) -> Bool { false }

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
