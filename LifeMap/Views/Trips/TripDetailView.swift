import SwiftUI
import MapKit

/// One trip: its path on a map with song markers, followed by every song heard.
struct TripDetailView: View {
    let trip: Trip
    var filter: TripFilter = TripFilter()

    @State private var onlyMatching: Bool
    @State private var selectedListenID: UUID?

    init(trip: Trip, filter: TripFilter = TripFilter()) {
        self.trip = trip
        self.filter = filter
        self.onlyMatching = !filter.isDefault
    }

    private var listens: [ListeningEvent] {
        onlyMatching ? filter.matchingListens(in: trip) : trip.orderedListens
    }

    var body: some View {
        List {
            Section {
                TripMap(trip: trip, listens: listens, selectedListenID: $selectedListenID)
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
            }

            Section("Summary") {
                LabeledContent("Started", value: trip.startDate.formatted(date: .abbreviated, time: .shortened))
                if let end = trip.endDate {
                    LabeledContent("Ended", value: end.formatted(date: .omitted, time: .shortened))
                }
                LabeledContent("Duration", value: Formatters.duration(trip.duration))
                LabeledContent("Distance", value: Formatters.distance(trip.distanceMeters))
                LabeledContent("Points recorded", value: trip.pointCount.formatted())
                LabeledContent("Started by", value: trip.trigger.displayName)
                if let activity = trip.activity {
                    LabeledContent("Activity", value: activity.displayName)
                }
            }

            Section {
                if !filter.isDefault {
                    Toggle("Only show matching songs", isOn: $onlyMatching)
                }
                if listens.isEmpty {
                    ContentUnavailableView(
                        "No songs",
                        systemImage: "music.note",
                        description: Text(onlyMatching ? "No songs on this trip match the filter." : "Nothing was playing during this trip.")
                    )
                } else {
                    ForEach(listens) { listen in
                        ListenRow(listen: listen, isHighlighted: selectedListenID == listen.id || (!filter.isDefault && filter.matches(listen)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedListenID = selectedListenID == listen.id ? nil : listen.id
                            }
                    }
                }
            } header: {
                Text("Songs (\(listens.count))")
            }
        }
        .navigationTitle(trip.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Map of a single trip with a marker where each song started.
private struct TripMap: View {
    let trip: Trip
    let listens: [ListeningEvent]
    @Binding var selectedListenID: UUID?

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position, selection: $selectedListenID) {
            let coordinates = trip.coordinates
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(TripPalette.color(for: trip), lineWidth: 4)
            }
            if let first = coordinates.first {
                Marker("Start", systemImage: "flag", coordinate: first)
                    .tint(.green)
            }
            if coordinates.count > 1, let last = coordinates.last {
                Marker("End", systemImage: "flag.checkered", coordinate: last)
                    .tint(.red)
            }
            ForEach(listens) { listen in
                if let coordinate = listen.startCoordinate ?? trip.nearestPoint(to: listen.startedAt)?.coordinate {
                    Annotation(listen.title, coordinate: coordinate, anchor: .bottom) {
                        SongPin(listen: listen, isSelected: selectedListenID == listen.id)
                    }
                    .tag(listen.id)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onChange(of: selectedListenID) { _, newValue in
            guard let newValue,
                  let listen = listens.first(where: { $0.id == newValue }),
                  let coordinate = listen.startCoordinate else { return }
            withAnimation {
                position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
            }
        }
    }
}

struct SongPin: View {
    let listen: ListeningEvent
    var isSelected = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(listen.source.tint)
                Circle()
                    .trim(from: 0, to: listen.fractionListened)
                    .stroke(.white, lineWidth: 3)
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                Image(systemName: "music.note")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: isSelected ? 34 : 26, height: isSelected ? 34 : 26)
            .shadow(radius: 2)
            Triangle()
                .fill(listen.source.tint)
                .frame(width: 10, height: 6)
        }
        .animation(.snappy, value: isSelected)
        .accessibilityLabel("\(listen.title), \(Formatters.percent(listen.fractionListened)) listened")
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
