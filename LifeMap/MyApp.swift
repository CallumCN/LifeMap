import SwiftUI
import SwiftData
import AppIntents

@main
struct MyApp: App {
    private let container: ModelContainer
    private let settings: AppSettings
    private let coordinator: TrackingCoordinator

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Trip.self, TrackPoint.self, ListeningEvent.self)
        } catch {
            fatalError("Could not open the LifeMap data store: \(error)")
        }
        let settings = AppSettings()
        let coordinator = TrackingCoordinator(settings: settings, modelContext: container.mainContext)
        // Make the coordinator available to App Intents run from Shortcuts.
        AppDependencyManager.shared.add(dependency: coordinator)

        self.container = container
        self.settings = settings
        self.coordinator = coordinator
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(coordinator)
                .onOpenURL { url in
                    // Spotify returns here after being launched to accept a connection.
                    coordinator.playback.appRemote.handleCallback(url: url)
                }
                .onChange(of: scenePhase) { _, phase in
                    // iOS drops the App Remote connection in the background.
                    if phase == .active {
                        coordinator.playback.appRemote.reconnectIfNeeded()
                    }
                }
        }
        .modelContainer(container)
    }
}
