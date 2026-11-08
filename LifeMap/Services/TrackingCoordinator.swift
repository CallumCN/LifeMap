import Foundation
import CoreLocation
import SwiftData
import Observation

/// Decides *when* to record based on the user's tracking mode, and wires location,
/// motion, now-playing polling, trip persistence, and live sharing together.
@Observable
final class TrackingCoordinator {
    let settings: AppSettings
    let location = LocationTracker()
    let motion = MotionActivityMonitor()
    let listening = ListeningTracker()
    let recorder: TripRecorder
    let liveShare: LiveShareService

    let appleMusic: AppleMusicNowPlayingProvider
    let spotify: SpotifyNowPlayingProvider
    let youtubeMusic: YouTubeMusicNowPlayingProvider
    /// Replays recorded songs on their original service.
    let playback: MusicPlaybackService

    /// Why the current trip is being recorded, or `nil` when idle.
    private(set) var activeTrigger: TrackingTrigger?
    private(set) var trackingStartedAt: Date?

    private var idleWatchTask: Task<Void, Never>?
    private var motionStoppedAt: Date?

    init(settings: AppSettings, modelContext: ModelContext) {
        self.settings = settings
        self.recorder = TripRecorder(modelContext: modelContext)
        self.liveShare = LiveShareService(settings: settings)
        self.appleMusic = AppleMusicNowPlayingProvider()
        let spotify = SpotifyNowPlayingProvider(settings: settings)
        self.spotify = spotify
        self.youtubeMusic = YouTubeMusicNowPlayingProvider()
        self.playback = MusicPlaybackService(spotify: spotify)

        location.onLocation = { [weak self] location in
            self?.handle(location: location)
        }
        motion.onChange = { [weak self] activity in
            self?.handle(activity: activity)
        }
        listening.onListenCompleted = { [weak self] listen in
            self?.recorder.add(listen)
        }
        listening.locationProvider = { [weak self] in
            self?.location.latestLocation
        }

        observeSettings()
        applyMode()
    }

    var isTracking: Bool { activeTrigger != nil }

    var allProviders: [any NowPlayingProvider] {
        [appleMusic, spotify, youtubeMusic]
    }

    func provider(for source: MusicSource) -> any NowPlayingProvider {
        switch source {
        case .appleMusic: appleMusic
        case .spotify: spotify
        case .youtubeMusic: youtubeMusic
        }
    }

    private var enabledProviders: [any NowPlayingProvider] {
        allProviders.filter { settings.enabledSources.contains($0.source) }
    }

    // MARK: - Mode handling

    /// Re-evaluates the tracking mode. Safe to call repeatedly.
    func applyMode() {
        switch settings.trackingMode {
        case .manual:
            motion.stop()
            if let trigger = activeTrigger, trigger == .always || trigger == .motion {
                stopTracking()
            }

        case .always:
            location.holdAlwaysAuthorization()
            // Motion stays on so trips can be labelled with an activity.
            motion.start(detectTrains: false)
            if activeTrigger != .always {
                if isTracking { stopTracking() }
                startTracking(trigger: .always, activity: motion.current)
            }

        case .onMotion:
            location.holdAlwaysAuthorization()
            motion.stop()
            motion.start(detectTrains: settings.enabledActivities.contains(.train))
            if activeTrigger == .always {
                stopTracking()
            }
            if let current = motion.current, settings.enabledActivities.contains(current), !isTracking {
                startTracking(trigger: .motion, activity: current)
            } else if activeTrigger == .motion, let current = motion.current, !settings.enabledActivities.contains(current) {
                motionStoppedAt = motionStoppedAt ?? .now
            }

        case .whenMusicAppOpens:
            location.holdAlwaysAuthorization()
            motion.stop()
            if let trigger = activeTrigger, trigger == .always || trigger == .motion {
                stopTracking()
            }
        }
    }

    // MARK: - Start / stop

    func startTracking(trigger: TrackingTrigger, activity: MotionActivityKind? = nil) {
        guard !isTracking else { return }
        activeTrigger = trigger
        trackingStartedAt = .now
        motionStoppedAt = nil
        recorder.start(trigger: trigger, activity: activity ?? motion.current)
        location.start(configuration: LocationTracker.configuration(for: activity ?? motion.current, highPrecision: settings.highPrecision))
        listening.start(providers: enabledProviders)
        if settings.liveShareEnabled {
            liveShare.start()
        }
        startIdleWatch()
    }

    func stopTracking() {
        guard isTracking else { return }
        idleWatchTask?.cancel()
        idleWatchTask = nil
        // Stop listening first so the in-progress song is written before the trip closes.
        listening.stop()
        location.stop()
        liveShare.stop()
        recorder.end()
        activeTrigger = nil
        trackingStartedAt = nil
        motionStoppedAt = nil
    }

    func toggleManualTracking() {
        if isTracking {
            stopTracking()
        } else {
            startTracking(trigger: .manual)
        }
    }

    /// Entry point for the Shortcuts "Start Tracking" intent.
    func startFromShortcut() {
        let trigger: TrackingTrigger = settings.trackingMode == .whenMusicAppOpens ? .musicApp : .shortcut
        startTracking(trigger: trigger)
    }

    // MARK: - Event handling

    private func handle(location: CLLocation) {
        // In always-on mode a trip is closed when the user stops moving and a new one
        // opens on the next movement, so the list is a series of journeys, not one blob.
        if activeTrigger == .always, !recorder.isRecording, location.speed >= 1 {
            recorder.start(trigger: .always, activity: motion.current)
        }
        recorder.add(location)
        liveShare.update(location: location, nowPlaying: listening.current)
    }

    private func handle(activity: MotionActivityKind?) {
        recorder.updateActivity(activity)
        guard settings.trackingMode == .onMotion else { return }
        if let activity, settings.enabledActivities.contains(activity) {
            motionStoppedAt = nil
            if !isTracking {
                startTracking(trigger: .motion, activity: activity)
            }
        } else if activeTrigger == .motion {
            motionStoppedAt = motionStoppedAt ?? .now
        }
    }

    // MARK: - Idle detection

    private func startIdleWatch() {
        idleWatchTask?.cancel()
        idleWatchTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                self.checkIdle()
            }
        }
    }

    private func checkIdle() {
        guard let trigger = activeTrigger else { return }
        let idleLimit = TimeInterval(settings.idleStopMinutes * 60)
        let now = Date()

        switch trigger {
        case .manual, .shortcut:
            break

        case .musicApp:
            let reference = listening.lastPlayingAt ?? trackingStartedAt ?? now
            if now.timeIntervalSince(reference) > idleLimit {
                stopTracking()
            }

        case .motion:
            let stillSince = motionStoppedAt ?? recorder.lastMovementAt ?? now
            if now.timeIntervalSince(stillSince) > idleLimit {
                stopTracking()
            }

        case .always:
            if recorder.isRecording, let lastMovement = recorder.lastMovementAt, now.timeIntervalSince(lastMovement) > idleLimit {
                listening.stop()
                recorder.end()
                listening.start(providers: enabledProviders)
            }
        }
    }

    // MARK: - Settings observation

    private func observeSettings() {
        withObservationTracking {
            _ = settings.trackingMode
            _ = settings.enabledActivities
            _ = settings.enabledSources
            _ = settings.liveShareEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.settingsDidChange()
                strongSelf.observeSettings()
            }
        }
    }

    private func settingsDidChange() {
        applyMode()
        if isTracking {
            if settings.liveShareEnabled, !liveShare.isSharing {
                liveShare.start()
            } else if !settings.liveShareEnabled, liveShare.isSharing {
                liveShare.stop()
            }
        }
    }
}
