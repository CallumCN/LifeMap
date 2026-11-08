import SwiftUI
import SwiftData
import MapKit

/// Every filtered trip drawn on one map, with pins where matching songs started.
struct TripsMapView: View {
    @Binding var filter: TripFilter

    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @State private var position: MapCameraPosition = .automatic
    @State private var selection: MapSelectionItem?
    @State private var showingFilters = false
    @State private var showSongPins = true

    private var filteredTrips: [Trip] {
        filter.apply(to: trips)
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selection) {
                ForEach(filteredTrips) { trip in
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
            .overlay(alignment: .bottom) {
                if let selection {
                    selectionCard(for: selection)
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView("No trips yet", systemImage: "map", description: Text("Recorded trips will appear here."))
                        .background(.regularMaterial)
                }
            }
            .animation(.snappy, value: selection)
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.songQuery, prompt: "Song, artist, or album")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $showSongPins) {
                        Label("Song pins", systemImage: "music.note")
                    }
                    .toggleStyle(.button)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filter", systemImage: filter.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                TripFilterSheet(filter: $filter)
                    .presentationDetents([.medium, .large])
            }
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip, filter: filter)
            }
            .onChange(of: filter) { _, _ in
                selection = nil
                position = .automatic
            }
        }
    }

    /// The path, start marker, and song pins for one trip. Split out of `body` so the
    /// compiler can type-check the map content in reasonable time.
    @MapContentBuilder
    private func tripContent(for trip: Trip) -> some MapContent {
        let coordinates = trip.coordinates
        let color = TripPalette.color(for: trip)
        let tripItem = MapSelectionItem.trip(trip.id)
        let startLabel = trip.startDate.formatted(date: .abbreviated, time: .shortened)

        if coordinates.count > 1 {
            MapPolyline(coordinates: coordinates)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        if let start = coordinates.first {
            Annotation(startLabel, coordinate: start, anchor: .center) {
                TripStartDot(color: color, isSelected: selection == tripItem)
            }
            .tag(tripItem)
        }
        if showSongPins {
            ForEach(filter.matchingListens(in: trip)) { listen in
                songPin(for: listen, in: trip)
            }
        }
    }

    /// One song marker, placed where the song started or at the nearest recorded point.
    @MapContentBuilder
    private func songPin(for listen: ListeningEvent, in trip: Trip) -> some MapContent {
        let coordinate = listen.startCoordinate ?? trip.nearestPoint(to: listen.startedAt)?.coordinate
        if let coordinate {
            let listenItem = MapSelectionItem.listen(listen.id)
            Annotation(listen.title, coordinate: coordinate, anchor: .bottom) {
                SongPin(listen: listen, isSelected: selection == listenItem)
            }
            .tag(listenItem)
        }
    }

    @ViewBuilder
    private func selectionCard(for item: MapSelectionItem) -> some View {
        switch item {
        case .trip(let id):
            if let trip = trips.first(where: { $0.id == id }) {
                NavigationLink(value: trip) {
                    TripRowView(trip: trip, filter: filter)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        case .listen(let id):
            if let (trip, listen) = findListen(id) {
                NavigationLink(value: trip) {
                    ListenRow(listen: listen, isHighlighted: true)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func findListen(_ id: UUID) -> (Trip, ListeningEvent)? {
        for trip in filteredTrips {
            if let listen = trip.listens.first(where: { $0.id == id }) {
                return (trip, listen)
            }
        }
        return nil
    }
}

/// Selection token for the shared map: either a trip's start marker or a song pin.
enum MapSelectionItem: Hashable {
    case trip(UUID)
    case listen(UUID)
}

private struct TripStartDot: View {
    let color: Color
    var isSelected = false

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .frame(width: isSelected ? 20 : 14, height: isSelected ? 20 : 14)
            .shadow(radius: 2)
    }
}
