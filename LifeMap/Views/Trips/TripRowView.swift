import SwiftUI

struct TripRowView: View {
    let trip: Trip
    let filter: TripFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Formatters.tripTitle(start: trip.startDate, end: trip.endDate))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if trip.isActive {
                    Text("LIVE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 14) {
                metric("point.topleft.down.to.point.bottomright.curvepath", Formatters.distance(trip.distanceMeters))
                metric("clock", Formatters.duration(trip.duration))
                metric("music.note.list", "\(trip.listens.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// An icon and its value kept tight together, so the groups read as separate metrics.
    private func metric(_ symbolName: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
            Text(value)
        }
        .accessibilityElement(children: .combine)
    }
}
