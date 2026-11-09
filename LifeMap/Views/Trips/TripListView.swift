import SwiftUI
import SwiftData

/// All recorded trips, newest first, filterable by song and fraction listened.
struct TripListView: View {
    @Binding var filter: TripFilter

    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @State private var path: [Trip] = []
    @State private var editMode: EditMode = .inactive
    @State private var showingFilters = false
    /// Trips the user has asked to delete, awaiting confirmation.
    @State private var tripsPendingDeletion: [Trip] = []

    private var filteredTrips: [Trip] {
        filter.apply(to: trips)
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { !tripsPendingDeletion.isEmpty },
            set: { if !$0 { tripsPendingDeletion = [] } }
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                        Button {
                            path.append(trip)
                        } label: {
                            TripRowView(trip: trip, filter: filter)
                        }
                        .buttonStyle(.plain)
                        // The trip being recorded can't be deleted until tracking stops.
                        .deleteDisabled(trip.isActive)
                        .contextMenu {
                            Button("Delete Trip", systemImage: "trash", role: .destructive) {
                                tripsPendingDeletion = [trip]
                            }
                            .disabled(trip.isActive)
                        }
                    }
                    .onDelete(perform: requestDeletion)
                }
            }
            .environment(\.editMode, $editMode)
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "map")
                    } description: {
                        Text("Begin a trip from the Live tab, or choose an automatic mode in Settings.")
                    } actions: {
                        Button("Begin trip") {
                            navigation.selectedTab = .live
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredTrips.isEmpty {
                    ContentUnavailableView.search(text: filter.songQuery)
                }
            }
            .appTabBarInset()
            // The title is drawn as a toolbar item so the buttons sit on the same line as it.
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Trips")
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)

                // Separate items so each button gets its own background.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filter", systemImage: filter.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                if !trips.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(editMode.isEditing ? "Done" : "Manage") {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip, filter: filter)
            }
            .searchable(text: $filter.songQuery, prompt: "Song, artist, or album")
            .sheet(isPresented: $showingFilters) {
                TripFilterSheet(filter: $filter)
                    .presentationDetents([.medium, .large])
            }
            .alert(deletionTitle, isPresented: isConfirmingDeletion) {
                Button(deletionButtonTitle, role: .destructive, action: deletePendingTrips)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deletionMessage)
            }
        }
    }

    // MARK: - Deletion

    /// Called by swipe-to-delete and edit mode; asks for confirmation before removing anything.
    private func requestDeletion(at offsets: IndexSet) {
        let visible = filteredTrips
        tripsPendingDeletion = offsets.compactMap { visible.indices.contains($0) ? visible[$0] : nil }
    }

    private func deletePendingTrips() {
        for trip in tripsPendingDeletion where !trip.isActive {
            modelContext.delete(trip)
        }
        tripsPendingDeletion = []
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to delete trips: \(error)")
        }
        if trips.isEmpty {
            editMode = .inactive
        }
    }

    private var deletionTitle: String {
        tripsPendingDeletion.count == 1 ? "Delete this trip?" : "Delete \(tripsPendingDeletion.count) trips?"
    }

    private var deletionButtonTitle: String {
        tripsPendingDeletion.count == 1 ? "Delete Trip" : "Delete \(tripsPendingDeletion.count) Trips"
    }

    private var deletionMessage: String {
        if let trip = tripsPendingDeletion.first, tripsPendingDeletion.count == 1 {
            let when = trip.startDate.formatted(date: .abbreviated, time: .shortened)
            let songs = trip.listens.count == 1 ? "1 song" : "\(trip.listens.count) songs"
            return "\(when) · \(Formatters.distance(trip.distanceMeters)) · \(songs)\nThis can't be undone."
        }
        return "Their paths and songs will be removed. This can't be undone."
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
