import SwiftUI

/// A thin bar showing which stretches of a song were heard. Each observed range is drawn
/// where it falls in the song, so a play that began mid-song starts mid-bar and a skip
/// leaves a gap. With no range data it falls back to a plain fill from the left.
struct PlayedRangesBar: View {
    let ranges: [PlayedRange]
    let durationSeconds: Double
    /// Drawn as a left-anchored fill when `ranges` is empty, such as for plays recorded
    /// before ranges were tracked or imported from a history API.
    let fallbackFraction: Double
    let tint: Color

    private let height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                if ranges.isEmpty || durationSeconds <= 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: width * clamped(fallbackFraction))
                } else {
                    ForEach(ranges.merged(), id: \.self) { range in
                        let leading = width * clamped(range.start / durationSeconds)
                        let trailing = width * clamped(range.end / durationSeconds)
                        Capsule()
                            .fill(tint)
                            .frame(width: max(trailing - leading, height))
                            .offset(x: min(leading, width - height))
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func clamped(_ fraction: Double) -> CGFloat {
        CGFloat(min(1, max(0, fraction)))
    }
}

#Preview {
    VStack(spacing: 16) {
        PlayedRangesBar(ranges: [], durationSeconds: 240, fallbackFraction: 0.6, tint: .pink)
        PlayedRangesBar(ranges: [PlayedRange(start: 90, end: 150)], durationSeconds: 240, fallbackFraction: 0, tint: .green)
        PlayedRangesBar(
            ranges: [PlayedRange(start: 0, end: 40), PlayedRange(start: 120, end: 200), PlayedRange(start: 230, end: 240)],
            durationSeconds: 240,
            fallbackFraction: 0,
            tint: .pink
        )
    }
    .padding()
}
