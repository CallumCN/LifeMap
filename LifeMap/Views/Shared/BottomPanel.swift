import SwiftUI

/// Resting positions for `BottomPanel`.
enum PanelDetent: CaseIterable {
    case collapsed
    case half
    case full
}

/// A panel that floats over the bottom of a map and can be dragged between showing just
/// its header, half the available height, and nearly all of it.
struct BottomPanel<Header: View, Content: View>: View {
    @Binding var detent: PanelDetent
    /// Height of the area the panel lives in, usually from a `GeometryReader` around the map.
    let availableHeight: CGFloat
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0

    /// Height needed to show the grabber and the header.
    static var collapsedHeight: CGFloat { 84 }

    private func height(for detent: PanelDetent) -> CGFloat {
        switch detent {
        case .collapsed: Self.collapsedHeight
        case .half: max(Self.collapsedHeight, availableHeight * 0.5)
        case .full: max(Self.collapsedHeight, availableHeight - 24)
        }
    }

    private var currentHeight: CGFloat {
        min(max(height(for: detent) - dragOffset, Self.collapsedHeight), height(for: .full))
    }

    private var showsContent: Bool {
        detent != .collapsed || dragOffset < 0
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                header()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(drag)

            if showsContent {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: currentHeight, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .accessibilityAction(named: detent == .full ? "Collapse" : "Expand") {
            withAnimation(.snappy) {
                detent = detent == .full ? .collapsed : .full
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let projected = height(for: detent) - value.predictedEndTranslation.height
                let nearest = PanelDetent.allCases.min {
                    abs(height(for: $0) - projected) < abs(height(for: $1) - projected)
                } ?? .collapsed
                withAnimation(.snappy) {
                    detent = nearest
                    dragOffset = 0
                }
            }
    }
}
