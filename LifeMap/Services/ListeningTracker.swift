import Foundation
import CoreLocation
import Observation

/// A finished play, ready to be stored as a `ListeningEvent`.
struct CompletedListen: Sendable {
    var snapshot: NowPlayingSnapshot
    var startedAt: Date
    var endedAt: Date
    var listenedSeconds: Double
    /// Stretches of the track observed playing, merged and in order. Empty when the
    /// service reported no playhead position.
    var playedRanges: [PlayedRange]
    var startLocation: CLLocation?
    var endLocation: CLLocation?

    var fraction: Double {
        ListeningEvent.fraction(listened: listenedSeconds, duration: snapshot.durationSeconds ?? 0)
    }
}

/// Polls the enabled music services while a trip is active and turns the stream of
/// now-playing snapshots into discrete plays, each with the stretches of the track that
/// were actually observed playing.
///
/// Only what happens while polling is recorded. A play begins at the first position seen
/// playing, or at the paused position from the previous poll if the same track was sitting
/// there, and nothing before that is assumed. When the playhead moves further than the
/// elapsed time allows, or rewinds, a new range begins, so skips show up as gaps. Services
/// that report no playhead position fall back to crediting wall-clock time with no ranges.
@Observable
final class ListeningTracker {
    private(set) var isRunning = false
    private(set) var current: NowPlayingSnapshot?
    private(set) var currentListenedSeconds: Double = 0
    /// Ranges of the current play observed so far, merged and in order.
    private(set) var currentRanges: [PlayedRange] = []
    private(set) var lastPollError: String?
    /// The moment music was last observed playing; used to end music-triggered trips.
    private(set) var lastPlayingAt: Date?

    var onListenCompleted: ((CompletedListen) -> Void)?
    /// Supplies the most recent location so plays can be pinned to the map.
    var locationProvider: (() -> CLLocation?)?

    private var providers: [any NowPlayingProvider] = []
    private var pollTask: Task<Void, Never>?
    private var active: ActiveListen?
    /// The last paused snapshot seen while nothing was being recorded, so a play that
    /// resumes from that position can start its range there rather than one poll later.
    private var lastIdleSnapshot: NowPlayingSnapshot?
    private var lastIdleSeenAt: Date?
    private let pollInterval: Duration

    /// Playhead movement beyond this multiple of elapsed time, plus a second of slack, is a seek.
    private static let seekTolerance = 1.5
    /// Rewinding further than this is treated as restarting the song, which counts as a new play.
    private static let restartThreshold: Double = 20
    /// Ranges shorter than this are where a seek landed, not listening, and are dropped.
    private static let minimumRangeSeconds: Double = 1

    private struct ActiveListen {
        var snapshot: NowPlayingSnapshot
        var startedAt: Date
        var lastSeen: Date
        /// Observed stretches in the order they happened. The last one is still open.
        var ranges: [PlayedRange]
        /// Wall-clock seconds credited when the service reports no playhead position.
        var untimedSeconds: Double
        var startLocation: CLLocation?

        var hasPositions: Bool { !ranges.isEmpty }

        var listenedSeconds: Double {
            hasPositions ? ranges.coveredSeconds : untimedSeconds
        }

        mutating func extendOpenRange(to position: Double) {
            if ranges.isEmpty {
                ranges.append(PlayedRange(start: position, end: position))
            } else {
                ranges[ranges.count - 1].end = max(ranges[ranges.count - 1].end, position)
            }
        }
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
        lastIdleSnapshot = nil
        lastIdleSeenAt = nil
        current = nil
        publishIdle()
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
            lastIdleSnapshot = nil
            lastIdleSeenAt = nil
            publishIdle()
            return
        }

        if var active {
            let sameTrack = active.snapshot.isSameTrack(as: snapshot)
            // A big backwards jump on the same track means it was restarted: count a new play.
            let restarted: Bool = {
                guard sameTrack, let old = active.snapshot.positionSeconds, let new = snapshot.positionSeconds else { return false }
                return old - new > Self.restartThreshold
            }()
            if !sameTrack || restarted {
                finishActive(at: now)
            } else {
                let elapsed = now.timeIntervalSince(active.lastSeen)
                if let old = active.snapshot.positionSeconds, let new = snapshot.positionSeconds {
                    if new >= old, new - old <= elapsed * Self.seekTolerance + 1 {
                        // The playhead advanced about as far as time passed: extend the open range.
                        if new > old {
                            active.extendOpenRange(to: new)
                        }
                    } else {
                        // Jumped further ahead than could have played, or rewound a little:
                        // whatever was in between wasn't heard, so open a new range here.
                        active.ranges.append(PlayedRange(start: new, end: new))
                    }
                } else if snapshot.isPlaying {
                    active.untimedSeconds += elapsed
                }
                active.snapshot = snapshot
                active.lastSeen = now
                self.active = active
                publish(active)
                return
            }
        }

        // Only start a new play once the track is actually playing. A paused or stopped
        // track with no play in progress is just whatever the music app last had loaded,
        // which can be a song left half-finished months ago.
        guard snapshot.isPlaying else {
            lastIdleSnapshot = snapshot
            lastIdleSeenAt = now
            current = nil
            publishIdle()
            return
        }

        // Begin at the first observed position. If the previous poll saw this same track
        // paused just behind here, playback resumed from that spot, so start there instead.
        var ranges: [PlayedRange] = []
        if let position = snapshot.positionSeconds {
            var start = position
            if let idle = lastIdleSnapshot, let idleAt = lastIdleSeenAt,
               idle.isSameTrack(as: snapshot),
               let idlePosition = idle.positionSeconds,
               idlePosition <= position,
               position - idlePosition <= now.timeIntervalSince(idleAt) * Self.seekTolerance + 1 {
                start = idlePosition
            }
            ranges = [PlayedRange(start: start, end: position)]
        }
        lastIdleSnapshot = nil
        lastIdleSeenAt = nil

        let listen = ActiveListen(
            snapshot: snapshot,
            startedAt: now,
            lastSeen: now,
            ranges: ranges,
            untimedSeconds: 0,
            startLocation: locationProvider?()
        )
        active = listen
        publish(listen)
    }

    private func finishActive(at date: Date) {
        guard let active else { return }
        self.active = nil
        let ranges = active.ranges
            .filter { $0.length >= Self.minimumRangeSeconds }
            .merged()
        let listened = active.hasPositions ? ranges.coveredSeconds : active.untimedSeconds
        // Ignore blips shorter than a couple of seconds (e.g. skipping through a playlist).
        guard listened >= 2 else { return }
        let completed = CompletedListen(
            snapshot: active.snapshot,
            startedAt: active.startedAt,
            endedAt: date,
            listenedSeconds: listened,
            playedRanges: ranges,
            startLocation: active.startLocation,
            endLocation: locationProvider?()
        )
        onListenCompleted?(completed)
    }

    private func publish(_ active: ActiveListen) {
        currentListenedSeconds = active.listenedSeconds
        currentRanges = active.ranges.merged()
    }

    private func publishIdle() {
        currentListenedSeconds = 0
        currentRanges = []
    }
}
