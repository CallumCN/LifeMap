import SwiftUI

/// A song in a trip, with artwork and a bar showing how much of it was heard.
struct ListenRow: View {
    let listen: ListeningEvent
    var isHighlighted = false
    /// Colour matching this song's stretch of the route on the map, when shown alongside one.
    var accent: Color?

    var body: some View {
        HStack(spacing: 12) {
            if let accent {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }
            ArtworkThumbnail(url: listen.artworkURL, source: listen.source)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(listen.title)
                    .font(.body.weight(isHighlighted ? .semibold : .regular))
                    .lineLimit(1)
                Text(listen.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    PlayedRangesBar(
                        ranges: listen.observedRanges,
                        durationSeconds: listen.durationSeconds,
                        fallbackFraction: listen.fractionListened,
                        tint: listen.source.tint
                    )
                    Text(Formatters.percent(listen.fractionListened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if listen.isEstimated {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Estimated")
                    }
                }
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text(listen.startedAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SourceBadge(source: listen.source)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(listen.title) by \(listen.artist), \(Formatters.percent(listen.fractionListened)) listened, \(listen.source.displayName)")
    }
}

struct SourceBadge: View {
    let source: MusicSource

    var body: some View {
        Image(systemName: source.symbolName)
            .font(.caption)
            .foregroundStyle(source.tint)
            .accessibilityLabel(source.displayName)
    }
}

struct ArtworkThumbnail: View {
    let url: URL?
    let source: MusicSource

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(source.tint.opacity(0.15))
                    .overlay {
                        Image(systemName: source.symbolName)
                            .foregroundStyle(source.tint)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
