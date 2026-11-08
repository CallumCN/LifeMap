import SwiftUI
import SwiftData
import AppIntents
import CoreLocation

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TrackingCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    @State private var errorMessage: String?
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                trackingSection(settings: $settings)
                sourcesSection(settings: $settings)
                liveShareSection(settings: $settings)
                shortcutsSection
                dataSection
            }
            .navigationTitle("Settings")
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog("Delete all trips?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive, action: deleteAllTrips)
            } message: {
                Text("This removes every recorded trip, path, and song. It can't be undone.")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func trackingSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            Picker("Track location", selection: settings.trackingMode) {
                ForEach(TrackingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if settings.wrappedValue.trackingMode == .onMotion {
                ForEach(MotionActivityKind.allCases) { kind in
                    Toggle(isOn: activityBinding(kind, settings: settings)) {
                        Label(kind.displayName, systemImage: kind.symbolName)
                    }
                }
                if !coordinator.motion.isAvailable {
                    Label("Motion detection isn't available on this device.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Toggle("High-precision paths", isOn: settings.highPrecision)

            Stepper(value: settings.idleStopMinutes, in: 1...30) {
                LabeledContent("Auto-stop after", value: "\(settings.wrappedValue.idleStopMinutes) min idle")
            }
        } header: {
            Text("Location tracking")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(settings.wrappedValue.trackingMode.detail)
                if settings.wrappedValue.trackingMode == .onMotion, settings.wrappedValue.enabledActivities.contains(.train) {
                    Text("Train travel isn't something the motion sensors can classify directly. LifeMap infers it when you're moving faster than about 40 km/h without walking, running, or cycling, using the low-power significant-change location service.")
                }
                Text("High-precision mode uses navigation-grade GPS. Turn it off for longer battery life on walks and runs.")
            }
        }
    }

    @ViewBuilder
    private func sourcesSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            ForEach(MusicSource.allCases) { source in
                MusicSourceRow(
                    source: source,
                    provider: coordinator.provider(for: source),
                    isEnabled: sourceBinding(source, settings: settings),
                    onError: { errorMessage = $0 }
                )
            }
        } header: {
            Text("Music sources")
        } footer: {
            Text("Apple Music reads the system player, so it also covers songs from your library. Spotify opens a sign-in page in an in-app browser. YouTube Music has no public API for playback or history.")
        }
    }

    @ViewBuilder
    private func liveShareSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            Toggle("Share live location + music", isOn: settings.liveShareEnabled)
            TextField("https://example.com/lifemap/live", text: settings.liveShareEndpoint)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.callout.monospaced())
        } header: {
            Text("Live sharing")
        } footer: {
            Text("While a trip is being recorded, LifeMap pairs your latest position with the song playing and POSTs it as JSON to this HTTPS endpoint every 10 seconds. Point it at a small server or function you control, then build a viewer page on top of it.")
        }
    }

    private var shortcutsSection: some View {
        Section {
            ShortcutsLink()
            VStack(alignment: .leading, spacing: 6) {
                Text("To track whenever you open a music app:")
                    .font(.subheadline.weight(.semibold))
                Text("1. Set “Track location” above to “When a music app opens”.")
                Text("2. In Shortcuts → Automation → New, choose “App”, pick Spotify, Music, or YouTube Music, and “Is Opened”.")
                Text("3. Add the action “Start LifeMap Tracking” and turn off “Ask Before Running”.")
                Text("Tracking ends automatically once music has been paused for the auto-stop interval, or when you run “Stop LifeMap Tracking”.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Shortcuts")
        }
    }

    private var dataSection: some View {
        Section {
            Button("Delete all trips", role: .destructive) {
                confirmDeleteAll = true
            }
            .disabled(coordinator.isTracking)
        } header: {
            Text("Data")
        } footer: {
            Text("All trips are stored on this device only.")
        }
    }

    // MARK: - Bindings & actions

    private func activityBinding(_ kind: MotionActivityKind, settings: Bindable<AppSettings>) -> Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.enabledActivities.contains(kind) },
            set: { isOn in
                if isOn {
                    settings.wrappedValue.enabledActivities.insert(kind)
                } else {
                    settings.wrappedValue.enabledActivities.remove(kind)
                }
            }
        )
    }

    private func sourceBinding(_ source: MusicSource, settings: Bindable<AppSettings>) -> Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.enabledSources.contains(source) },
            set: { isOn in
                if isOn {
                    settings.wrappedValue.enabledSources.insert(source)
                } else {
                    settings.wrappedValue.enabledSources.remove(source)
                }
            }
        )
    }

    private func deleteAllTrips() {
        do {
            try modelContext.delete(model: Trip.self)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Connection status and connect/disconnect control for one music service.
private struct MusicSourceRow: View {
    let source: MusicSource
    let provider: any NowPlayingProvider
    @Binding var isEnabled: Bool
    let onError: (String) -> Void

    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isEnabled) {
                Label(source.displayName, systemImage: source.symbolName)
            }
            .tint(source.tint)

            HStack {
                statusLabel
                Spacer()
                actionButton
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch provider.connectionState {
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .connecting:
            Label("Connecting…", systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
        case .notConnected:
            Label("Not connected", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .unavailable(let reason):
            Label(reason, systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch provider.connectionState {
        case .connected where source != .appleMusic:
            Button("Disconnect") {
                provider.disconnect()
            }
        case .notConnected, .connecting:
            Button("Connect") {
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    do {
                        try await provider.connect()
                    } catch {
                        onError(error.localizedDescription)
                    }
                }
            }
            .disabled(isWorking)
        default:
            EmptyView()
        }
    }
}
