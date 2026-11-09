import SwiftUI

/// Stable, distinguishable colours for drawing several trips on one map.
enum TripPalette {
    private static let colors: [Color] = [.blue, .orange, .purple, .teal, .pink, .indigo, .mint, .brown]

    static func color(for trip: Trip) -> Color {
        colors[abs(trip.id.hashValue) % colors.count]
    }

    /// Spreads the rainbow across a span of dates: the oldest purple, the newest red.
    /// Pass the full range of recorded trips so colour reads as age at a glance.
    static func color(for date: Date, in range: ClosedRange<Date>?) -> Color {
        guard let range else { return Color(hue: 0, saturation: 0.85, brightness: 0.9) }
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        let fraction = span > 0
            ? min(1, max(0, date.timeIntervalSince(range.lowerBound) / span))
            : 1
        // 280° (purple) down through blue, green and yellow to 0° (red).
        return Color(hue: (280.0 / 360.0) * (1 - fraction), saturation: 0.85, brightness: 0.9)
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
