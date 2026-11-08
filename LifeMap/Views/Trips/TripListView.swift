import SwiftUI
import SwiftData

/// All recorded trips, newest first, filterable by song and fraction listened.
struct TripListView: View {
    @Binding var filter: TripFilter

    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    @Environment(TrackingCoordinator.self) private var coordinator
    @State private var showingFilters = false

    private var filteredTrips: [Trip] {
        filter.apply(to: trips)
    }

    var body: some View {
        NavigationStack {
            List {
                if !filter.isDefault {
                    Section {
                        FilterSummaryRow(filter: filter, matchCount: filteredTrips.count, totalCount: trips.count) {
                            filter = TripFilter()
                        }
                    }
                }

                Section {
                    ForEach(filteredTrips) { trip in
                        NavigationLink(value: trip) {
                            TripRowView(trip: trip, filter: filter)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "map")
                    } description: {
                        Text("Start tracking from the Live tab, or choose an automatic mode in Settings.")
                    } actions: {
                        Button("Start tracking") {
                            coordinator.startTracking(trigger: .manual)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredTrips.isEmpty {
                    ContentUnavailableView.search(text: filter.songQuery)
                }
            }
            .navigationTitle("Trips")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip, filter: filter)
            }
            .searchable(text: $filter.songQuery, prompt: "Song, artist, or album")
            .toolbar {
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
        }
    }

    private func delete(at offsets: IndexSet) {
        let visible = filteredTrips
        for index in offsets {
            let trip = visible[index]
            // Never delete the trip that's being recorded.
            if trip.isActive { continue }
            modelContext.delete(trip)
        }
        try? modelContext.save()
    }
}

/// Shows what the current filter is doing and offers a one-tap reset.
struct FilterSummaryRow: View {
    let filter: TripFilter
    let matchCount: Int
    let totalCount: Int
    let onReset: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(matchCount) of \(totalCount) trips")
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset", action: onReset)
                .font(.caption)
        }
    }

    private var description: String {
        var parts: [String] = []
        let query = filter.songQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { parts.append("“\(query)”") }
        if filter.minFraction > 0 || filter.maxFraction < 1 {
            parts.append("\(Formatters.percent(filter.minFraction))–\(Formatters.percent(filter.maxFraction)) listened")
        }
        if filter.sources.count < MusicSource.allCases.count {
            parts.append(filter.sources.map(\.displayName).sorted().joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}
