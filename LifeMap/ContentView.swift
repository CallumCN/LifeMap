import SwiftUI
import SwiftData

/// The app's top-level tabs, so views can send the user to another tab.
enum AppTab: Hashable {
    case trips
    case map
    case live
    case settings
}

struct ContentView: View {
    @State private var filter = TripFilter()
    @State private var selectedTab: AppTab = .trips

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Trips", systemImage: "list.bullet.rectangle", value: .trips) {
                TripListView(filter: $filter, selectedTab: $selectedTab)
            }
            Tab("Map", systemImage: "map", value: .map) {
                TripsMapView(filter: $filter)
            }
            Tab("Live", systemImage: "dot.radiowaves.left.and.right", value: .live) {
                LiveView()
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard)
    let container = try! ModelContainer(
        for: Trip.self, TrackPoint.self, ListeningEvent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let coordinator = TrackingCoordinator(settings: settings, modelContext: container.mainContext)
    ContentView()
        .environment(settings)
        .environment(coordinator)
        .modelContainer(container)
}
