import Foundation
import SwiftUI

/// Where the music that was playing came from.
enum MusicSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleMusic
    case spotify
    case youtubeMusic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .youtubeMusic: "YouTube Music"
        }
    }

    var symbolName: String {
        switch self {
        case .appleMusic: "music.note"
        case .spotify: "waveform"
        case .youtubeMusic: "play.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .appleMusic: .pink
        case .spotify: .green
        case .youtubeMusic: .red
        }
    }
}

/// The kinds of movement that can automatically start a trip.
enum MotionActivityKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case walking
    case running
    case cycling
    case automotive
    case train

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .automotive: "Driving"
        case .train: "Train"
        }
    }

    var symbolName: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "bicycle"
        case .automotive: "car"
        case .train: "tram"
        }
    }
}

/// How the app decides when to record location.
enum TrackingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Only record when the user taps Start.
    case manual
    /// Record continuously, splitting trips when the user stops moving.
    case always
    /// Record while the user is doing one of the enabled motion activities.
    case onMotion
    /// Record when a music app is opened. Driven by a Shortcuts automation that
    /// runs the app's Start Tracking intent, because iOS does not let one app
    /// observe another app being launched.
    case whenMusicAppOpens

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: "Manually"
        case .always: "All the time"
        case .onMotion: "When moving"
        case .whenMusicAppOpens: "When a music app opens"
        }
    }

    var detail: String {
        switch self {
        case .manual:
            "Location is only recorded between Start and Stop."
        case .always:
            "Location is recorded continuously. Uses the most battery."
        case .onMotion:
            "Location is recorded while the phone detects one of the activities you pick below."
        case .whenMusicAppOpens:
            "Create a Shortcuts automation: When Spotify / Music / YouTube Music is opened → Run “Start LifeMap Tracking”. Tracking stops after music has been paused for a few minutes."
        }
    }
}

/// What caused a trip to start. Stored on each trip so it can be shown in the list.
enum TrackingTrigger: String, Codable, CaseIterable, Sendable {
    case manual
    case always
    case motion
    case musicApp
    case shortcut

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .always: "Always on"
        case .motion: "Motion"
        case .musicApp: "Music app"
        case .shortcut: "Shortcut"
        }
    }
}
