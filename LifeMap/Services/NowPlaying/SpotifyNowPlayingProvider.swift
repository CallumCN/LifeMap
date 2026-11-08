import Foundation
import Observation
import CryptoKit
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Talks to the Spotify Web API using the Authorization Code + PKCE flow, which needs
/// only a client ID (no secret) and is the flow Spotify recommends for mobile apps.
///
/// Set up: create an app at developer.spotify.com, add `lifemap://spotify-callback`
/// as a Redirect URI, and paste the Client ID into LifeMap's settings.
@Observable
final class SpotifyNowPlayingProvider: NowPlayingProvider {
    let source: MusicSource = .spotify
    private(set) var connectionState: NowPlayingConnectionState = .notConnected

    private let settings: AppSettings
    private var tokens: SpotifyTokens?
    /// Kept alive for the duration of a sign-in because the session only holds it weakly.
    private var presentationContext: WebAuthPresentationContext?

    private static let tokenKey = "spotify.tokens"
    private static let scopes = "user-read-currently-playing user-read-playback-state user-read-recently-played"

    init(settings: AppSettings) {
        self.settings = settings
        tokens = KeychainStore.loadCodable(SpotifyTokens.self, for: Self.tokenKey)
        connectionState = tokens == nil ? .notConnected : .connected
    }

    // MARK: - Connection

    func connect() async throws {
        let clientID = AppSettings.spotifyClientID
        guard !clientID.isEmpty else {
            throw SpotifyError.missingClientID
        }
        connectionState = .connecting
        do {
            let verifier = PKCE.codeVerifier()
            let challenge = PKCE.codeChallenge(for: verifier)
            let state = UUID().uuidString

            var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: AppSettings.spotifyRedirectURI),
                URLQueryItem(name: "scope", value: Self.scopes),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "state", value: state),
            ]

            let callbackURL = try await authenticate(url: components.url!)
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            let items = callbackComponents?.queryItems ?? []
            guard items.first(where: { $0.name == "state" })?.value == state else {
                throw SpotifyError.stateMismatch
            }
            if let errorValue = items.first(where: { $0.name == "error" })?.value {
                throw SpotifyError.authorizationFailed(errorValue)
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                throw SpotifyError.authorizationFailed("missing code")
            }

            let newTokens = try await exchange(code: code, verifier: verifier, clientID: clientID)
            try store(newTokens)
            connectionState = .connected
        } catch {
            connectionState = .notConnected
            throw error
        }
    }

    func disconnect() {
        tokens = nil
        KeychainStore.delete(Self.tokenKey)
        connectionState = .notConnected
    }

    private func authenticate(url: URL) async throws -> URL {
        guard let anchor = Self.presentationAnchor() else {
            throw SpotifyError.authorizationFailed("no window is available to show the sign-in page")
        }
        let context = WebAuthPresentationContext(anchor: anchor)
        presentationContext = context
        defer { presentationContext = nil }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme("lifemap")) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: SpotifyError.authorizationFailed("no callback"))
                }
            }
            session.presentationContextProvider = context
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    /// The window the OAuth sheet should attach to, or `nil` when the app has no visible scene.
    private static func presentationAnchor() -> ASPresentationAnchor? {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return nil
        }
        return scene.keyWindow ?? scene.windows.first ?? UIWindow(windowScene: scene)
        #else
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
        #endif
    }

    // MARK: - Tokens

    private func exchange(code: String, verifier: String, clientID: String) async throws -> SpotifyTokens {
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": AppSettings.spotifyRedirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]
        return try await requestTokens(form: body)
    }

    private func refreshIfNeeded() async throws -> String {
        guard let tokens else { throw SpotifyError.notConnected }
        if tokens.expiresAt.timeIntervalSinceNow > 60 {
            return tokens.accessToken
        }
        guard let refreshToken = tokens.refreshToken else { throw SpotifyError.notConnected }
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": AppSettings.spotifyClientID,
        ]
        var refreshed = try await requestTokens(form: body)
        if refreshed.refreshToken == nil {
            refreshed.refreshToken = refreshToken
        }
        try store(refreshed)
        return refreshed.accessToken
    }

    private func requestTokens(form: [String: String]) async throws -> SpotifyTokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyError.httpError(message)
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return SpotifyTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }

    private func store(_ newTokens: SpotifyTokens) throws {
        tokens = newTokens
        try KeychainStore.saveCodable(newTokens, for: Self.tokenKey)
    }

    // MARK: - Now playing

    func currentlyPlaying() async throws -> NowPlayingSnapshot? {
        guard connectionState.isConnected else { return nil }
        let token = try await refreshIfNeeded()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        switch http.statusCode {
        case 204:
            return nil
        case 401:
            disconnect()
            throw SpotifyError.notConnected
        case 200..<300:
            break
        default:
            throw SpotifyError.httpError(String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
        }

        let playing = try JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data)
        guard let item = playing.item, playing.currently_playing_type == "track" else { return nil }
        return NowPlayingSnapshot(
            source: .spotify,
            trackID: item.id,
            title: item.name,
            artist: item.artists.map(\.name).joined(separator: ", "),
            album: item.album?.name,
            artworkURL: item.album?.images.first.flatMap { URL(string: $0.url) },
            durationSeconds: Double(item.duration_ms) / 1000,
            positionSeconds: playing.progress_ms.map { Double($0) / 1000 },
            isPlaying: playing.is_playing,
            observedAt: .now
        )
    }

    /// Fetches tracks Spotify reports as played after the given date. Spotify only
    /// records tracks played for 30 seconds or more and doesn't report how much was heard.
    func recentlyPlayed(after date: Date) async throws -> [RecentPlay] {
        guard connectionState.isConnected else { return [] }
        let token = try await refreshIfNeeded()
        let afterMillis = Int(date.timeIntervalSince1970 * 1000)
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/recently-played")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "after", value: String(afterMillis)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpotifyError.httpError(String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(RecentlyPlayedResponse.self, from: data)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        return decoded.items.compactMap { item in
            guard let playedAt = formatter.date(from: item.played_at) ?? fallback.date(from: item.played_at) else {
                return nil
            }
            return RecentPlay(
                trackID: item.track.id,
                title: item.track.name,
                artist: item.track.artists.map(\.name).joined(separator: ", "),
                album: item.track.album?.name,
                artworkURL: item.track.album?.images.first.flatMap { URL(string: $0.url) },
                durationSeconds: Double(item.track.duration_ms) / 1000,
                // Spotify reports the time the track finished playing.
                endedAt: playedAt
            )
        }
    }

    struct RecentPlay: Sendable {
        var trackID: String
        var title: String
        var artist: String
        var album: String?
        var artworkURL: URL?
        var durationSeconds: Double
        var endedAt: Date
    }

    // MARK: - Wire types

    private struct SpotifyTokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
    }

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int
    }

    private struct CurrentlyPlayingResponse: Decodable {
        var is_playing: Bool
        var progress_ms: Int?
        var currently_playing_type: String?
        var item: TrackObject?
    }

    private struct RecentlyPlayedResponse: Decodable {
        var items: [PlayHistoryObject]
    }

    private struct PlayHistoryObject: Decodable {
        var played_at: String
        var track: TrackObject
    }

    private struct TrackObject: Decodable {
        var id: String
        var name: String
        var duration_ms: Int
        var artists: [ArtistObject]
        var album: AlbumObject?
    }

    private struct ArtistObject: Decodable {
        var name: String
    }

    private struct AlbumObject: Decodable {
        var name: String
        var images: [ImageObject]
    }

    private struct ImageObject: Decodable {
        var url: String
    }

    enum SpotifyError: LocalizedError {
        case missingClientID
        case notConnected
        case stateMismatch
        case authorizationFailed(String)
        case httpError(String)

        var errorDescription: String? {
            switch self {
            case .missingClientID:
                "Enter your Spotify Client ID in Settings first."
            case .notConnected:
                "Spotify is not connected."
            case .stateMismatch:
                "Spotify sign-in returned an unexpected response."
            case .authorizationFailed(let reason):
                "Spotify sign-in failed: \(reason)"
            case .httpError(let message):
                "Spotify request failed: \(message)"
            }
        }
    }
}

/// Generates the PKCE verifier/challenge pair.
private enum PKCE {
    static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    /// RFC 3986 unreserved characters, safe for form-encoded values.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}

/// Hands the OAuth web view a window that was resolved before sign-in began.
private nonisolated final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
