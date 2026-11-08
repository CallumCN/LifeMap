import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var filter = TripFilter()

    var body: some View {
        TabView {
            Tab("Trips", systemImage: "list.bullet.rectangle") {
                TripListView(filter: $filter)
            }
            Tab("Map", systemImage: "map") {
                TripsMapView(filter: $filter)
            }
            Tab("Live", systemImage: "dot.radiowaves.left.and.right") {
                LiveView()
            }
            Tab("Settings", systemImage: "gear") {
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
