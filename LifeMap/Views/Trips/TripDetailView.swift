import SwiftUI
import MapKit
import CoreLocation

/// One trip as a full-screen map: the route coloured by the song playing along each
/// stretch, a replay control, and a draggable panel listing the songs.
struct TripDetailView: View {
    let trip: Trip
    var filter: TripFilter = TripFilter()

    @Environment(TrackingCoordinator.self) private var coordinator
    @Environment(AppNavigation.self) private var navigation
    @State private var replayer: TripReplayer?
    @State private var segments: [RouteSegment] = []
    @State private var colors: [UUID: Color] = [:]
    @State private var startCoordinate: CLLocationCoordinate2D?
    @State private var endCoordinate: CLLocationCoordinate2D?
    @State private var detent: PanelDetent = .collapsed
    @State private var position: MapCameraPosition = .automatic
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []

    private var listens: [ListeningEvent] {
        trip.orderedListens
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                tripMap
                    // A constant inset: the map's frame never changes, so neither the panel
                    // drag nor the camera animation can make it re-lay out. Only the camera
                    // region changes when the panel settles.
                    .safeAreaPadding(.bottom, BottomPanelMetrics.defaultCollapsedHeight)

                BottomPanel(detent: $detent, availableHeight: proxy.size.height, fillsToBottomEdge: true) {
                    panelHeader
                } content: {
                    songList
                } accessory: {
                    if detent != .full {
                        replayButton
                    }
                }
            }
        }
        .navigationTitle(Formatters.tripTitle(start: trip.startDate, end: trip.endDate))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            navigation.isTabBarHidden = true
        }
        .onChange(of: detent) { _, newDetent in
            // Once the panel settles at the bottom or middle, refit the route into the part
            // of the map the panel leaves visible.
            guard newDetent != .full else { return }
            let coverage = newDetent == .half ? 0.45 : 0.0
            guard let region = RouteMath.region(fitting: routeCoordinates, bottomCoverage: coverage) else { return }
            withAnimation(.snappy) {
                position = .region(region)
            }
        }
        .task {
            let points = trip.orderedPoints
            startCoordinate = points.first?.coordinate
            endCoordinate = points.count > 1 ? points.last?.coordinate : nil
            routeCoordinates = points.map(\.coordinate)
            segments = trip.routeSegments()
            colors = Dictionary(uniqueKeysWithValues: listens.enumerated().map { ($1.id, SongPalette.color(at: $0)) })
            replayer = TripReplayer(trip: trip, playback: coordinator.playback)
        }
        .onDisappear {
            replayer?.stop()
            navigation.isTabBarHidden = false
        }
    }

    private var tripMap: some View {
            Map(position: $position) {
                ForEach(segments) { segment in
                    if segment.coordinates.count > 1 {
                        MapPolyline(coordinates: segment.coordinates)
                            .stroke(color(for: segment.listen), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
                if let startCoordinate {
                    Marker("Start", systemImage: "flag", coordinate: startCoordinate)
                        .tint(.green)
                }
                if let endCoordinate {
                    Marker("End", systemImage: "flag.checkered", coordinate: endCoordinate)
                        .tint(.red)
                }
                if let coordinate = replayer?.currentCoordinate {
                    Annotation("Replay position", coordinate: coordinate, anchor: .center) {
                        ReplayDot(color: replayer?.currentListen.flatMap { colors[$0.id] } ?? .black)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private func color(for listen: ListeningEvent?) -> Color {
        listen.flatMap { colors[$0.id] } ?? SongPalette.silence
    }


    // MARK: - Replay

    @ViewBuilder
    private var replayButton: some View {
        if let replayer, replayer.canReplay {
            Button {
                if replayer.isPlaying {
                    replayer.stop()
                } else {
                    replayer.play()
                }
            } label: {
                Image(systemName: replayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(replayer.isPlaying ? "Pause replay" : "Replay trip")
        }
    }

    // MARK: - Panel

    private var panelHeader: some View {
        HStack {
            Text("Songs")
                .font(.headline)
            Spacer()
            if let current = replayer?.currentListen {
                Text(current.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var songList: some View {
        VStack(spacing: 0) {
            if let error = coordinator.playback.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if listens.isEmpty {
                // Bounded and top-aligned: the panel is laid out at full height, so an
                // unbounded empty state would centre itself below the screen.
                ContentUnavailableView("No songs", systemImage: "music.note", description: Text("Nothing was playing during this trip."))
                    .frame(height: BottomPanelMetrics.emptyStateHeight)
                Spacer(minLength: 0)
            } else {
                List(listens) { listen in
                    Button {
                        replayer?.play(from: listen)
                    } label: {
                        ListenRow(
                            listen: listen,
                            isHighlighted: replayer?.currentListen?.id == listen.id,
                            accent: colors[listen.id]
                        )
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

/// The moving marker shown while a trip is being replayed.
private struct ReplayDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .frame(width: 18, height: 18)
            .shadow(radius: 3)
    }
}
