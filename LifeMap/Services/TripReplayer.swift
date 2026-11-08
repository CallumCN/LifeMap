import Foundation
import CoreLocation
import Observation

/// Replays a finished trip in real time: a position that moves along the route at the
/// recorded pace, with the song that was playing at each moment started on its service.
@Observable
final class TripReplayer {
    private(set) var isPlaying = false
    /// The moment of the trip currently being replayed, or `nil` when idle.
    private(set) var currentDate: Date?
    private(set) var currentCoordinate: CLLocationCoordinate2D?
    private(set) var currentListen: ListeningEvent?

    private let trip: Trip
    private let playback: MusicPlaybackService
    private let points: [TrackPoint]
    private let listens: [ListeningEvent]
    private var task: Task<Void, Never>?

    private static let tick: Duration = .milliseconds(250)
    /// If a song was first seen within this many seconds of its start, replay it from the top.
    private static let leadInThreshold: Double = 5

    init(trip: Trip, playback: MusicPlaybackService) {
        self.trip = trip
        self.playback = playback
        self.points = trip.orderedPoints
        self.listens = trip.orderedListens
    }

    var canReplay: Bool {
        points.count > 1
    }

    private var endDate: Date {
        trip.endDate ?? points.last?.timestamp ?? trip.startDate
    }

    /// Starts, or resumes, from `date`. Pass `nil` to resume where it paused or begin at the start.
    func play(from date: Date? = nil) {
        task?.cancel()
        let start = date ?? currentDate ?? trip.startDate
        currentDate = start
        update(to: start)
        isPlaying = true

        task = Task { [weak self] in
            var lastTick = Date()
            var playingListenID: UUID? = UUID()  // Sentinel so the first song always starts.
            var playingSegment = -1
            while let self, !Task.isCancelled {
                let now = Date()
                let elapsed = now.timeIntervalSince(lastTick)
                lastTick = now

                guard let position = self.currentDate?.addingTimeInterval(elapsed) else { break }
                if position >= self.endDate {
                    self.finish()
                    break
                }
                self.update(to: position)

                if let listen = self.currentListen {
                    let playhead = self.playhead(for: listen, at: position)
                    if listen.id != playingListenID {
                        // A different song: start it where the recording says it was.
                        playingListenID = listen.id
                        playingSegment = playhead.segment
                        await self.playback.play(listen, offsetSeconds: playhead.offset)
                    } else if playhead.segment != playingSegment {
                        // Same song, but the recording jumped here: reproduce the skip.
                        playingSegment = playhead.segment
                        await self.playback.seek(to: playhead.offset)
                    }
                } else if playingListenID != nil {
                    playingListenID = nil
                    playingSegment = -1
                    await self.playback.stop()
                }
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    /// Where the song's playhead was at a moment of the trip, following the recorded
    /// stretches in order so that skips are reproduced. Returns which stretch the moment
    /// falls in, so callers can detect when a jump happens.
    private func playhead(for listen: ListeningEvent, at date: Date) -> (segment: Int, offset: Double) {
        var elapsed = max(0, date.timeIntervalSince(listen.startedAt))
        var ranges = listen.observedRanges
        guard !ranges.isEmpty else { return (0, elapsed) }

        // A song caught just after it began is treated as heard from the top.
        if ranges[0].start <= Self.leadInThreshold {
            ranges[0].start = 0
        }
        for (index, range) in ranges.enumerated() {
            let isLast = index == ranges.count - 1
            if elapsed < range.length || isLast {
                return (index, range.start + elapsed)
            }
            elapsed -= range.length
        }
        return (ranges.count - 1, ranges[ranges.count - 1].end)
    }

    /// Jumps to the moment a song began and plays from there.
    func play(from listen: ListeningEvent) {
        play(from: listen.startedAt)
    }

    /// Pauses, keeping the current position so `play()` resumes.
    func stop() {
        task?.cancel()
        task = nil
        isPlaying = false
        Task { await playback.stop() }
    }

    private func finish() {
        task = nil
        isPlaying = false
        currentDate = nil
        currentCoordinate = nil
        currentListen = nil
        Task { await playback.stop() }
    }

    private func update(to date: Date) {
        currentDate = date
        currentCoordinate = RouteMath.coordinate(at: date, in: points)
        currentListen = listens.first { $0.startedAt <= date && date <= $0.endedAt }
    }
}
