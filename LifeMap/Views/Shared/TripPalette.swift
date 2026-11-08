import SwiftUI

/// Stable, distinguishable colours for drawing several trips on one map.
enum TripPalette {
    private static let colors: [Color] = [.blue, .orange, .purple, .teal, .pink, .indigo, .mint, .brown]

    static func color(for trip: Trip) -> Color {
        colors[abs(trip.id.hashValue) % colors.count]
    }
}
