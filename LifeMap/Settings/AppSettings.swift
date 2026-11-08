import Foundation
import Observation

/// User preferences, persisted in UserDefaults and observable by the UI and the tracking engine.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    private enum Key {
        static let trackingMode = "trackingMode"
        static let enabledActivities = "enabledActivities"
        static let enabledSources = "enabledSources"
        static let liveShareEnabled = "liveShareEnabled"
        static let liveShareEndpoint = "liveShareEndpoint"
        static let spotifyClientID = "spotifyClientID"
        static let highPrecision = "highPrecision"
        static let idleStopMinutes = "idleStopMinutes"
    }

    var trackingMode: TrackingMode {
        didSet { defaults.set(trackingMode.rawValue, forKey: Key.trackingMode) }
    }

    /// Activities that start tracking when `trackingMode == .onMotion`.
    var enabledActivities: Set<MotionActivityKind> {
        didSet { defaults.set(enabledActivities.map(\.rawValue).sorted(), forKey: Key.enabledActivities) }
    }

    /// Music services whose now-playing state is polled while tracking.
    var enabledSources: Set<MusicSource> {
        didSet { defaults.set(enabledSources.map(\.rawValue).sorted(), forKey: Key.enabledSources) }
    }

    var liveShareEnabled: Bool {
        didSet { defaults.set(liveShareEnabled, forKey: Key.liveShareEnabled) }
    }

    /// Optional HTTPS endpoint that receives live location + now-playing JSON while sharing.
    var liveShareEndpoint: String {
        didSet { defaults.set(liveShareEndpoint, forKey: Key.liveShareEndpoint) }
    }

    /// Optional override for the built-in Spotify client ID, for developers testing
    /// against their own Spotify app. Leave empty to use `spotifyDefaultClientID`.
    var spotifyClientID: String {
        didSet { defaults.set(spotifyClientID, forKey: Key.spotifyClientID) }
    }

    /// The client ID actually used for Spotify sign-in: the override if set, else the built-in one.
    var effectiveSpotifyClientID: String {
        let override = spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? Self.spotifyDefaultClientID : override
    }

    /// When true, requests navigation-grade location fixes; otherwise fitness-grade (less battery).
    var highPrecision: Bool {
        didSet { defaults.set(highPrecision, forKey: Key.highPrecision) }
    }

    /// Minutes of no movement (or no music, in music-app mode) before a trip auto-ends.
    var idleStopMinutes: Int {
        didSet { defaults.set(idleStopMinutes, forKey: Key.idleStopMinutes) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        trackingMode = defaults.string(forKey: Key.trackingMode).flatMap(TrackingMode.init(rawValue:)) ?? .manual
        let activityRaws = defaults.stringArray(forKey: Key.enabledActivities)
        enabledActivities = activityRaws.map { Set($0.compactMap(MotionActivityKind.init(rawValue:))) }
            ?? [.automotive, .cycling, .train]
        let sourceRaws = defaults.stringArray(forKey: Key.enabledSources)
        enabledSources = sourceRaws.map { Set($0.compactMap(MusicSource.init(rawValue:))) }
            ?? Set(MusicSource.allCases)
        liveShareEnabled = defaults.bool(forKey: Key.liveShareEnabled)
        liveShareEndpoint = defaults.string(forKey: Key.liveShareEndpoint) ?? ""
        spotifyClientID = defaults.string(forKey: Key.spotifyClientID) ?? ""
        highPrecision = defaults.object(forKey: Key.highPrecision) as? Bool ?? true
        let idle = defaults.integer(forKey: Key.idleStopMinutes)
        idleStopMinutes = idle == 0 ? 5 : idle
    }

    /// Redirect URI registered with Spotify. Must match the URL scheme in Info.plist.
    static let spotifyRedirectURI = "lifemap://spotify-callback"

    /// Client ID of the LifeMap app registered at developer.spotify.com. The app uses the
    /// PKCE flow, so this is public and no client secret is ever stored on the device.
    static let spotifyDefaultClientID = "28af32200f0340e1b8eb6ea3e0b3a1de"
}
