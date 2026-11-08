import AppIntents

/// Starts a trip. Designed to be run from a Shortcuts automation such as
/// "When Spotify is opened → Start LifeMap Tracking", which is how the
/// "when a music app opens" tracking mode works.
struct StartTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start LifeMap Tracking"
    static let description = IntentDescription("Begins recording your location and the music you're listening to.")
    static let supportedModes: IntentModes = .background

    @Dependency private var coordinator: TrackingCoordinator

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if await coordinator.isTracking {
            return .result(dialog: "LifeMap is already tracking.")
        }
        await coordinator.startFromShortcut()
        return .result(dialog: "LifeMap started tracking.")
    }
}

/// Ends the current trip.
struct StopTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop LifeMap Tracking"
    static let description = IntentDescription("Ends the current trip and stops recording location.")
    static let supportedModes: IntentModes = .background

    @Dependency private var coordinator: TrackingCoordinator

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await coordinator.isTracking else {
            return .result(dialog: "LifeMap wasn't tracking.")
        }
        await coordinator.stopTracking()
        return .result(dialog: "LifeMap stopped tracking.")
    }
}

/// Reports whether a trip is being recorded, for use in Shortcuts logic.
struct IsTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Is LifeMap Tracking"
    static let description = IntentDescription("Returns whether LifeMap is currently recording a trip.")
    static let supportedModes: IntentModes = .background

    @Dependency private var coordinator: TrackingCoordinator

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let tracking = await coordinator.isTracking
        return .result(value: tracking)
    }
}

struct LifeMapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTrackingIntent(),
            phrases: [
                "Start tracking in \(.applicationName)",
                "Start a \(.applicationName) trip",
            ],
            shortTitle: "Start Tracking",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: StopTrackingIntent(),
            phrases: [
                "Stop tracking in \(.applicationName)",
                "End my \(.applicationName) trip",
            ],
            shortTitle: "Stop Tracking",
            systemImageName: "stop.circle"
        )
    }
}
