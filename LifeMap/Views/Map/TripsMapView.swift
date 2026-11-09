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
    /// Route geometry cached per trip. Recomputing this inside the map content builder
    /// made every animation frame rebuild every polyline, which is what made the map stutter.
    @State private var routes: [UUID: TripRoute] = [:]
    @State private var dateRange: ClosedRange<Date>?
    /// Ranking is also cached, for the same reason as the routes.
    @State private var rankedEntries: [RankedEntry] = []
    @FocusState private var isSearchFocused: Bool

    /// Everything the map needs to draw one trip, worked out once.
    struct TripRoute {
        var coordinates: [CLLocationCoordinate2D]
        var segments: [RouteSegment]
        var color: Color
        var title: String
    }

    /// Tall enough for the Songs/Artists switch and the search field.
    private static let collapsedPanelHeight: CGFloat = 136

    private var entries: [RankedEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rankedEntries }
        return rankedEntries.filter { entry in
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
                    // A constant inset: the map's frame never changes, so neither the panel
                    // drag nor the camera animation can make it re-lay out.
                    .safeAreaPadding(.bottom, Self.collapsedPanelHeight)

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
                // The panel extends past the bottom of this area; keep it off the tab bar.
                .clipped()
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
            .onChange(of: ranking) { _, newRanking in
                selectedEntryID = nil
                rankedEntries = RankedEntry.rank(trips.flatMap(\.listens), by: newRanking)
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
                // Once the panel settles at the bottom or middle, refit the trips into the
                // part of the map the panel leaves visible.
                guard newDetent != .full else { return }
                let coverage = newDetent == .half ? 0.45 : 0.0
                let coordinates = routes.values.flatMap(\.coordinates)
                guard let region = RouteMath.region(fitting: coordinates, bottomCoverage: coverage) else { return }
                withAnimation(.snappy) {
                    position = .region(region)
                }
            }
            .task(id: trips.count) {
                rebuildRoutes()
            }
            .onChange(of: selectedTripID) { _, id in
                // Tapping a trip's start marker opens that trip.
                guard let id, let trip = trips.first(where: { $0.id == id }) else { return }
                selectedTripID = nil
                path.append(trip)
            }
        }
    }

    /// Works out each trip's geometry and colour once, instead of on every frame.
    private func rebuildRoutes() {
        let dates = trips.map(\.startDate).sorted()
        let range = dates.first.flatMap { first in dates.last.map { first...$0 } }
        dateRange = range
        rankedEntries = RankedEntry.rank(trips.flatMap(\.listens), by: ranking)
        routes = Dictionary(uniqueKeysWithValues: trips.map { trip in
            (trip.id, TripRoute(
                coordinates: trip.coordinates,
                segments: trip.routeSegments(),
                color: TripPalette.color(for: trip.startDate, in: range),
                title: Formatters.tripTitle(start: trip.startDate, end: trip.endDate)
            ))
        })
    }

    // MARK: - Map content

    @MapContentBuilder
    private func tripContent(for trip: Trip) -> some MapContent {
        if let route = routes[trip.id] {
            if let entry = selectedEntry {
                ForEach(route.segments) { segment in
                    segmentContent(segment, highlighting: entry)
                }
            } else if route.coordinates.count > 1 {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(route.color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            if let start = route.coordinates.first {
                Annotation(route.title, coordinate: start, anchor: .center) {
                    TripStartDot(color: route.color)
                }
                .tag(trip.id)
            }
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
                // Bounded and top-aligned; see the note in TripDetailView.
                Group {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView("No songs", systemImage: "music.note", description: Text("Songs heard on trips will be ranked here by time listened."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .frame(height: BottomPanelMetrics.emptyStateHeight)
                Spacer(minLength: 0)
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
