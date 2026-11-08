import SwiftUI

/// Stable, distinguishable colours for drawing several trips on one map.
enum TripPalette {
    private static let colors: [Color] = [.blue, .orange, .purple, .teal, .pink, .indigo, .mint, .brown]

    static func color(for trip: Trip) -> Color {
        colors[abs(trip.id.hashValue) % colors.count]
    }
}

/// Distinct colours for the songs within one trip, assigned by the order they were heard.
enum SongPalette {
    private static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown]

    static func color(at index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    /// Line colour for stretches of a route where nothing was playing.
    static let silence = Color.black.opacity(0.35)

    /// Line colour for the song or artist picked out on the Map tab.
    static let highlight = Color.accentColor
}
