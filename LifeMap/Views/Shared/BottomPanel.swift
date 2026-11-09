import SwiftUI

/// Sizes other views need to lay out around a `BottomPanel`.
enum BottomPanelMetrics {
    /// Height of a collapsed panel with a single-line header: the grabber plus the header.
    static let defaultCollapsedHeight: CGFloat = 84

    /// The panel's height at a resting position. `full` covers the whole available area.
    static func height(for detent: PanelDetent, collapsedHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        switch detent {
        case .collapsed: collapsedHeight
        case .half: max(collapsedHeight, availableHeight * 0.5)
        case .full: max(collapsedHeight, availableHeight)
        }
    }
}

/// Resting positions for `BottomPanel`.
enum PanelDetent: CaseIterable {
    case collapsed
    case half
    case full
}

/// A panel anchored to the bottom of a map that can be dragged between showing just its
/// header, half the available height, and all of it. It spans the full width with only
/// its top corners rounded, so it reads as part of the screen rather than a card.
///
/// Place it in a `ZStack` over the map rather than as a safe-area inset, so the map's
/// frame doesn't change while the panel is being dragged.
struct BottomPanel<Header: View, Content: View, Accessory: View>: View {
    @Binding var detent: PanelDetent
    /// Height of the area the panel lives in, usually from a `GeometryReader` around the map.
    let availableHeight: CGFloat
    /// Height when collapsed; raise it for headers taller than one line.
    var collapsedHeight: CGFloat
    /// When true, the background runs under the home indicator to the screen's bottom edge.
    /// Leave false when another bar, such as the tab bar, sits beneath the panel.
    var fillsToBottomEdge: Bool
    let header: () -> Header
    let content: () -> Content
    /// A control that floats just above the panel's top-left corner and moves with it.
    let accessory: () -> Accessory

    @State private var dragOffset: CGFloat = 0

    init(
        detent: Binding<PanelDetent>,
        availableHeight: CGFloat,
        collapsedHeight: CGFloat = BottomPanelMetrics.defaultCollapsedHeight,
        fillsToBottomEdge: Bool = false,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self._detent = detent
        self.availableHeight = availableHeight
        self.collapsedHeight = collapsedHeight
        self.fillsToBottomEdge = fillsToBottomEdge
        self.header = header
        self.content = content
        self.accessory = accessory
    }

    init(
        detent: Binding<PanelDetent>,
        availableHeight: CGFloat,
        collapsedHeight: CGFloat = BottomPanelMetrics.defaultCollapsedHeight,
        fillsToBottomEdge: Bool = false,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) where Accessory == EmptyView {
        self.init(
            detent: detent,
            availableHeight: availableHeight,
            collapsedHeight: collapsedHeight,
            fillsToBottomEdge: fillsToBottomEdge,
            header: header,
            content: content
        ) {
            EmptyView()
        }
    }

    private func height(for detent: PanelDetent) -> CGFloat {
        BottomPanelMetrics.height(for: detent, collapsedHeight: collapsedHeight, availableHeight: availableHeight)
    }

    private var currentHeight: CGFloat {
        min(max(height(for: detent) - dragOffset, collapsedHeight), height(for: .full))
    }

    private var showsContent: Bool {
        detent != .collapsed || dragOffset < 0
    }

    /// Square the top corners once the panel fills the area, so it reads as a full screen.
    private var cornerRadius: CGFloat {
        currentHeight >= height(for: .full) - 1 ? 0 : 20
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
        .clipped()
        .background {
            UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
                .fill(.regularMaterial)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
                        .stroke(.separator, lineWidth: 0.5)
                }
                .ignoresSafeArea(edges: fillsToBottomEdge ? .bottom : [])
        }
        .overlay(alignment: .topLeading) {
            // Sits above the panel, clear of the map attribution that hugs the panel's top edge.
            accessory()
                .padding(.leading, 16)
                .alignmentGuide(.top) { dimensions in dimensions[.bottom] + 40 }
        }
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
