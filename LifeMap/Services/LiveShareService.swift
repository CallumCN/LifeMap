import Foundation
import CoreLocation
import Observation

/// The JSON document published while live sharing is on.
struct LiveSharePayload: Codable, Equatable, Sendable {
    struct Track: Codable, Equatable, Sendable {
        var source: String
        var title: String
        var artist: String
        var album: String?
        var artworkURL: URL?
        var positionSeconds: Double?
        var durationSeconds: Double?
        var isPlaying: Bool
    }

    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var speedMetersPerSecond: Double?
    var course: Double?
    var track: Track?

    var shareText: String {
        var lines = ["📍 \(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))"]
        if let track {
            lines.append("🎵 \(track.title) — \(track.artist)")
        }
        lines.append("maps://?ll=\(latitude),\(longitude)")
        return lines.joined(separator: "\n")
    }
}

/// Pairs the current location with the current song and publishes it.
///
/// Publishing goes to an optional HTTPS endpoint of your choosing (a small server or
/// serverless function that stores the latest payload per user). Payloads are also kept
/// locally so the Live tab can preview exactly what is being shared, and offered through
/// the system share sheet as text.
@Observable
final class LiveShareService {
    private(set) var isSharing = false
    private(set) var latestPayload: LiveSharePayload?
    private(set) var lastPublishedAt: Date?
    private(set) var lastError: String?

    private let settings: AppSettings
    private var publishTask: Task<Void, Never>?
    /// Minimum time between network publishes.
    private static let publishInterval: TimeInterval = 10

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        isSharing = true
        lastError = nil
    }

    func stop() {
        isSharing = false
        publishTask?.cancel()
        publishTask = nil
        latestPayload = nil
    }

    func update(location: CLLocation?, nowPlaying: NowPlayingSnapshot?) {
        guard isSharing, let location else { return }
        let payload = LiveSharePayload(
            timestamp: .now,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            course: location.course >= 0 ? location.course : nil,
            track: nowPlaying.map {
                LiveSharePayload.Track(
                    source: $0.source.rawValue,
                    title: $0.title,
                    artist: $0.artist,
                    album: $0.album,
                    artworkURL: $0.artworkURL,
                    positionSeconds: $0.positionSeconds,
                    durationSeconds: $0.durationSeconds,
                    isPlaying: $0.isPlaying
                )
            }
        )
        latestPayload = payload
        publishIfDue(payload)
    }

    private func publishIfDue(_ payload: LiveSharePayload) {
        guard let url = endpointURL else { return }
        if let lastPublishedAt, Date().timeIntervalSince(lastPublishedAt) < Self.publishInterval {
            return
        }
        lastPublishedAt = .now
        publishTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                request.httpBody = try encoder.encode(payload)
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    self?.lastError = "Live share endpoint returned HTTP \(http.statusCode)"
                } else {
                    self?.lastError = nil
                }
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    private var endpointURL: URL? {
        let raw = settings.liveShareEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}
