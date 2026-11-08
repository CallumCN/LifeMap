import Foundation
import CoreLocation
import Observation

/// A finished play, ready to be stored as a `ListeningEvent`.
struct CompletedListen: Sendable {
    var snapshot: NowPlayingSnapshot
    var startedAt: Date
    var endedAt: Date
    var listenedSeconds: Double
    var startLocation: CLLocation?
    var endLocation: CLLocation?

    var fraction: Double {
        ListeningEvent.fraction(listened: listenedSeconds, duration: snapshot.durationSeconds ?? 0)
    }
}

/// Polls the enabled music services while a trip is active and turns the stream of
/// now-playing snapshots into discrete plays with a "fraction listened" measurement.
///
/// Listened time is accumulated from playhead progress between polls when the service
/// reports a position, and from wall-clock time otherwise. The position at the moment a
/// track is first seen counts as listened too, since the user heard it before we looked.
@Observable
final class ListeningTracker {
    private(set) var isRunning = false
    private(set) var current: NowPlayingSnapshot?
    private(set) var currentListenedSeconds: Double = 0
    private(set) var lastPollError: String?
    /// The moment music was last observed playing; used to end music-triggered trips.
    private(set) var lastPlayingAt: Date?

    var onListenCompleted: ((CompletedListen) -> Void)?
    /// Supplies the most recent location so plays can be pinned to the map.
    var locationProvider: (() -> CLLocation?)?

    private var providers: [any NowPlayingProvider] = []
    private var pollTask: Task<Void, Never>?
    private var active: ActiveListen?
    private let pollInterval: Duration

    private struct ActiveListen {
        var snapshot: NowPlayingSnapshot
        var startedAt: Date
        var lastSeen: Date
        var listenedSeconds: Double
        var startLocation: CLLocation?
    }

    init(pollInterval: Duration = .seconds(5)) {
        self.pollInterval = pollInterval
    }

    func start(providers: [any NowPlayingProvider]) {
        guard !isRunning else { return }
        self.providers = providers
        isRunning = true
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
        finishActive(at: .now)
        current = nil
        currentListenedSeconds = 0
    }

    /// One pass over the enabled providers; public so the UI can refresh on demand.
    func poll() async {
        var best: NowPlayingSnapshot?
        for provider in providers where provider.connectionState.isConnected {
            do {
                if let snapshot = try await provider.currentlyPlaying() {
                    // Prefer whichever source is actually playing.
                    if best == nil || (snapshot.isPlaying && !(best?.isPlaying ?? false)) {
                        best = snapshot
                    }
                }
            } catch {
                lastPollError = error.localizedDescription
            }
        }
        ingest(best)
    }

    private func ingest(_ snapshot: NowPlayingSnapshot?) {
        let now = Date()
        current = snapshot
        if snapshot?.isPlaying == true {
            lastPlayingAt = now
        }

        guard let snapshot else {
            finishActive(at: now)
            currentListenedSeconds = 0
            return
        }

        if var active {
            let sameTrack = active.snapshot.isSameTrack(as: snapshot)
            // A big backwards jump on the same track means it was restarted: count a new play.
            let restarted: Bool = {
                guard sameTrack, let old = active.snapshot.positionSeconds, let new = snapshot.positionSeconds else { return false }
                return old - new > 20
            }()
            if !sameTrack || restarted {
                finishActive(at: now)
            } else {
                let elapsed = now.timeIntervalSince(active.lastSeen)
                if snapshot.isPlaying || active.snapshot.isPlaying {
                    if let old = active.snapshot.positionSeconds, let new = snapshot.positionSeconds, new >= old {
                        // Cap at elapsed time so a seek forward isn't counted as listening.
                        active.listenedSeconds += min(new - old, elapsed * 1.5)
                    } else if snapshot.isPlaying {
                        active.listenedSeconds += elapsed
                    }
                }
                active.snapshot = snapshot
                active.lastSeen = now
                self.active = active
                currentListenedSeconds = active.listenedSeconds
                return
            }
        }

        // Only start a new play once the track is actually playing. A paused or stopped
        // track with no play in progress is just whatever the music app last had loaded,
        // which can be a song left half-finished months ago.
        guard snapshot.isPlaying else {
            current = nil
            currentListenedSeconds = 0
            return
        }

        // Start a new play.
        let seed = snapshot.positionSeconds ?? 0
        active = ActiveListen(
            snapshot: snapshot,
            startedAt: now.addingTimeInterval(-seed),
            lastSeen: now,
            listenedSeconds: seed,
            startLocation: locationProvider?()
        )
        currentListenedSeconds = seed
    }

    private func finishActive(at date: Date) {
        guard let active else { return }
        self.active = nil
        // Ignore blips shorter than a couple of seconds (e.g. skipping through a playlist).
        guard active.listenedSeconds >= 2 else { return }
        let completed = CompletedListen(
            snapshot: active.snapshot,
            startedAt: active.startedAt,
            endedAt: date,
            listenedSeconds: active.listenedSeconds,
            startLocation: active.startLocation,
            endLocation: locationProvider?()
        )
        onListenCompleted?(completed)
    }
}
