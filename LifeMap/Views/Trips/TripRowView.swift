import SwiftUI

struct TripRowView: View {
    let trip: Trip
    let filter: TripFilter

    private var matching: [ListeningEvent] {
        filter.matchingListens(in: trip)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: trip.activity?.symbolName ?? "location")
                .font(.title3)
                .foregroundStyle(TripPalette.color(for: trip))
                .frame(width: 32)
                .accessibilityLabel(trip.activity?.displayName ?? "Trip")

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

                HStack(spacing: 12) {
                    Label(Formatters.distance(trip.distanceMeters), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Label(Formatters.duration(trip.duration), systemImage: "clock")
                    Label("\(trip.listens.count)", systemImage: "music.note.list")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

                if !filter.isDefault, let first = matching.first {
                    HStack(spacing: 6) {
                        SourceBadge(source: first.source)
                        Text(first.title)
                            .lineLimit(1)
                        Text("· \(Formatters.percent(first.fractionListened))")
                            .foregroundStyle(.secondary)
                        if matching.count > 1 {
                            Text("+\(matching.count - 1) more")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                } else if let top = trip.orderedListens.max(by: { $0.fractionListened < $1.fractionListened }) {
                    HStack(spacing: 6) {
                        SourceBadge(source: top.source)
                        Text("\(top.title) — \(top.artist)")
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
