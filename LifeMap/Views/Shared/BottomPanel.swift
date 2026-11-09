import SwiftUI

/// Sizes other views need to lay out around a `BottomPanel`.
enum BottomPanelMetrics {
    /// Height of a collapsed panel with a single-line header: the grabber plus the header.
    static let defaultCollapsedHeight: CGFloat = 84

    /// Height to give an empty-state view inside a panel. The panel is laid out at full
    /// height, so a view that centres itself vertically needs bounding first.
    static let emptyStateHeight: CGFloat = 260

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
/// The panel is always laid out at full height and slid down to reveal only part of
/// itself. Dragging changes nothing but that offset, so no view inside it is ever
/// re-measured mid-gesture, which is what makes the slide smooth. The one resize happens
/// when a drag ends, instantly and while the panel is still off its resting place, so the
/// animation that follows is a pure transform.
///
/// Place it in a `ZStack` over the map rather than as a safe-area inset, so the map's
/// frame doesn't change either.
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

    private var fullHeight: CGFloat { height(for: .full) }
    private var settledHeight: CGFloat { height(for: detent) }

    /// How much of the panel is on screen right now, including any in-progress drag.
    private var visibleHeight: CGFloat {
        min(max(settledHeight - dragOffset, collapsedHeight), fullHeight)
    }

    private var cornerRadius: CGFloat { detent == .full ? 0 : 20 }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
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

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The panel is taller than the part on screen, so pad the scrollable area
                // by the hidden amount to keep every row reachable.
                .contentMargins(.bottom, fullHeight - settledHeight, for: .scrollContent)
        }
        .frame(height: fullHeight, alignment: .top)
        .clipShape(shape)
        .background(alignment: .top) {
            shape
                .fill(.regularMaterial)
                .overlay(alignment: .top) { Divider() }
                .ignoresSafeArea(edges: fillsToBottomEdge ? .bottom : [])
        }
        .overlay(alignment: .topLeading) {
            // Sits above the panel, clear of the map attribution that hugs its top edge.
            accessory()
                .padding(.leading, 16)
                .alignmentGuide(.top) { dimensions in dimensions[.bottom] + 40 }
        }
        .offset(y: fullHeight - visibleHeight)
        .accessibilityAction(named: detent == .full ? "Collapse" : "Expand") {
            setDetent(detent == .full ? .collapsed : .full, from: visibleHeight)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let released = visibleHeight
                let projected = settledHeight - value.predictedEndTranslation.height
                let nearest = PanelDetent.allCases.min {
                    abs(height(for: $0) - projected) < abs(height(for: $1) - projected)
                } ?? .collapsed
                setDetent(nearest, from: released)
            }
    }

    /// Resizes to the new resting height immediately while holding the panel visually
    /// still, then animates it into place without any further layout.
    private func setDetent(_ newDetent: PanelDetent, from visible: CGFloat) {
        detent = newDetent
        dragOffset = height(for: newDetent) - visible
        withAnimation(.snappy) {
            dragOffset = 0
        }
    }
}
