import SwiftUI
import SwiftData
import MapKit

/// Every trip on one map, with a panel ranking songs or artists by time heard. Picking one
/// highlights the stretches of route where it was playing.
struct TripsMapView: View {
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Environment(TrackingCoordinator.self) private var coordinator
    @State private var position: MapCameraPosition = .automatic
    @State private var path: [Trip] = []
    @State private var selectedTripID: UUID?
    @State private var detent: PanelDetent = .collapsed
    @State private var ranking: RankingKind = .songs
    @State private var query = ""
    @State private var selectedEntryID: String?
    @FocusState private var isSearchFocused: Bool

    /// Tall enough for the Songs/Artists switch and the search field.
    private static let collapsedPanelHeight: CGFloat = 136

    private var entries: [RankedEntry] {
        let ranked = RankedEntry.rank(trips.flatMap(\.listens), by: ranking)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ranked }
        return ranked.filter { entry in
            entry.title.localizedStandardContains(trimmed)
                || (ranking == .songs && entry.subtitle.localizedStandardContains(trimmed))
        }
    }

    private var selectedEntry: RankedEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Map(position: $position, selection: $selectedTripID) {
                        ForEach(trips) { trip in
                            tripContent(for: trip)
                        }
                        UserAnnotation()
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                    // Inset by the panel's resting height, so the map holds still during a drag.
                    .safeAreaPadding(.bottom, panelInset(availableHeight: proxy.size.height))

                    BottomPanel(
                        detent: $detent,
                        availableHeight: proxy.size.height,
                        collapsedHeight: Self.collapsedPanelHeight
                    ) {
                        panelHeader
                    } content: {
                        rankingList
                    } accessory: {
                        if detent != .full, let entry = selectedEntry {
                            playButton(for: entry)
                        }
                    }
                }
            }
            .appTabBarInset()
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView("No trips yet", systemImage: "map", description: Text("Recorded trips will appear here."))
                        .background(.regularMaterial)
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .onChange(of: ranking) { _, _ in
                selectedEntryID = nil
            }
            .onChange(of: isSearchFocused) { _, focused in
                // Typing into a collapsed panel would hide the results, so open it.
                if focused, detent == .collapsed {
                    withAnimation(.snappy) { detent = .half }
                }
            }
            .onChange(of: detent) { _, newDetent in
                if newDetent == .collapsed {
                    isSearchFocused = false
                }
                // Once the panel settles at the bottom or middle, show every trip again.
                guard newDetent != .full,
                      let region = RouteMath.region(fitting: trips.flatMap(\.coordinates)) else { return }
                withAnimation(.snappy) {
                    position = .region(region)
                }
            }
            .onChange(of: selectedTripID) { _, id in
                // Tapping a trip's start marker opens that trip.
                guard let id, let trip = trips.first(where: { $0.id == id }) else { return }
                selectedTripID = nil
                path.append(trip)
            }
        }
    }

    /// How much of the map's bottom the panel covers at its current resting position.
    private func panelInset(availableHeight: CGFloat) -> CGFloat {
        detent == .full
            ? 0
            : BottomPanelMetrics.height(for: detent, collapsedHeight: Self.collapsedPanelHeight, availableHeight: availableHeight)
    }

    // MARK: - Map content

    @MapContentBuilder
    private func tripContent(for trip: Trip) -> some MapContent {
        let tripColor = TripPalette.color(for: trip)
        let coordinates = trip.coordinates

        if let entry = selectedEntry {
            ForEach(trip.routeSegments()) { segment in
                segmentContent(segment, highlighting: entry)
            }
        } else if coordinates.count > 1 {
            MapPolyline(coordinates: coordinates)
                .stroke(tripColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }

        if let start = coordinates.first {
            Annotation(Formatters.tripTitle(start: trip.startDate, end: trip.endDate), coordinate: start, anchor: .center) {
                TripStartDot(color: tripColor)
            }
            .tag(trip.id)
        }
    }

    /// One stretch of a route: bold in the highlight colour when the chosen song or artist
    /// was playing, otherwise faint black.
    @MapContentBuilder
    private func segmentContent(_ segment: RouteSegment, highlighting entry: RankedEntry) -> some MapContent {
        if segment.coordinates.count > 1 {
            let highlighted = segment.listen.map(entry.matches) ?? false
            MapPolyline(coordinates: segment.coordinates)
                .stroke(
                    highlighted ? SongPalette.highlight : SongPalette.silence,
                    style: StrokeStyle(lineWidth: highlighted ? 5 : 3, lineCap: .round, lineJoin: .round)
                )
        }
    }

    // MARK: - Playback

    private func playButton(for entry: RankedEntry) -> some View {
        let playback = coordinator.playback
        let isPlayingThis = playback.isPlaying && playback.currentListenID == entry.topListen.id
        return Button {
            Task {
                if isPlayingThis {
                    await playback.stop()
                } else {
                    await playback.play(entry.topListen, offsetSeconds: 0)
                }
            }
        } label: {
            Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(isPlayingThis ? "Pause" : "Play \(entry.topListen.title)")
    }

    // MARK: - Ranking panel

    private var panelHeader: some View {
        VStack(spacing: 10) {
            Picker("Rank by", selection: $ranking) {
                ForEach(RankingKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(ranking == .songs ? "Search songs" : "Search artists", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var rankingList: some View {
        VStack(spacing: 0) {
            if let error = coordinator.playback.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if entries.isEmpty {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("No songs", systemImage: "music.note", description: Text("Songs heard on trips will be ranked here by time listened."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                List(entries) { entry in
                    RankedEntryRow(entry: entry, isSelected: entry.id == selectedEntryID)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isSearchFocused = false
                            selectedEntryID = selectedEntryID == entry.id ? nil : entry.id
                        }
                        .listRowBackground(entry.id == selectedEntryID ? Color.accentColor.opacity(0.12) : Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }
}

private struct RankedEntryRow: View {
    let entry: RankedEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let source = entry.source {
                    SourceBadge(source: source)
                } else {
                    Image(systemName: "music.mic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Formatters.duration(entry.seconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TripStartDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .frame(width: 14, height: 14)
            .shadow(radius: 2)
    }
}
