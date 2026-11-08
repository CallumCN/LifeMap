import SwiftUI
import MapKit
import CoreLocation

/// Tracking controls plus what's playing and where you are right now.
struct LiveView: View {
    @Environment(TrackingCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section {
                    trackingStatus
                    Button {
                        coordinator.toggleManualTracking()
                    } label: {
                        Label(
                            coordinator.isTracking ? "Stop tracking" : "Start tracking",
                            systemImage: coordinator.isTracking ? "stop.circle.fill" : "record.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(coordinator.isTracking ? .red : .accentColor)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Tracking")
                } footer: {
                    Text("Mode: \(settings.trackingMode.displayName). Change it in Settings.")
                }

                Section("Now playing") {
                    if let snapshot = coordinator.listening.current {
                        NowPlayingCard(snapshot: snapshot, listenedSeconds: coordinator.listening.currentListenedSeconds)
                    } else if coordinator.isTracking {
                        Text("Nothing playing on your connected services.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Music is only watched while tracking.")
                            .foregroundStyle(.secondary)
                    }
                    if let error = coordinator.listening.lastPollError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Location") {
                    liveMap
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                    if let location = coordinator.location.latestLocation {
                        LabeledContent("Coordinates") {
                            Text("\(location.coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(location.coordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                                .font(.callout.monospacedDigit())
                        }
                        LabeledContent("Accuracy", value: "±\(Formatters.distance(location.horizontalAccuracy))")
                        if location.speed >= 0 {
                            LabeledContent("Speed", value: Formatters.speed(location.speed))
                        }
                    } else {
                        Text(coordinator.isTracking ? "Waiting for a fix…" : "Location is only recorded while tracking.")
                            .foregroundStyle(.secondary)
                    }
                    if coordinator.location.authorizationDenied {
                        Label("Location access is denied. Enable it in Settings.", systemImage: "location.slash")
                            .foregroundStyle(.red)
                    } else if coordinator.location.accuracyLimited {
                        Label("Precise Location is off; paths will be approximate.", systemImage: "scope")
                            .foregroundStyle(.orange)
                    }
                    if let activity = coordinator.motion.current {
                        LabeledContent("Activity") {
                            Label(activity.displayName, systemImage: activity.symbolName)
                        }
                    }
                }

                Section {
                    Toggle("Share live location + music", isOn: $settings.liveShareEnabled)
                    if let payload = coordinator.liveShare.latestPayload {
                        ShareLink(item: payload.shareText, subject: Text("Where I am and what I'm hearing")) {
                            Label("Share a snapshot", systemImage: "square.and.arrow.up")
                        }
                        if let publishedAt = coordinator.liveShare.lastPublishedAt {
                            LabeledContent("Last published", value: publishedAt.formatted(date: .omitted, time: .standard))
                        }
                    }
                    if let error = coordinator.liveShare.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Live sharing")
                } footer: {
                    Text(liveShareFooter)
                }
            }
            .navigationTitle("Live")
        }
    }

    private var trackingStatus: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(coordinator.isTracking ? Color.red : Color.secondary)
                .frame(width: 12, height: 12)
                .overlay {
                    if coordinator.isTracking {
                        Circle()
                            .stroke(Color.red.opacity(0.4), lineWidth: 6)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.isTracking ? "Recording" : "Idle")
                    .font(.headline)
                if let trigger = coordinator.activeTrigger, let trip = coordinator.recorder.currentTrip {
                    Text("Started by \(trigger.displayName.lowercased()) · \(Formatters.distance(trip.distanceMeters)) · \(trip.pointCount) points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap Start to record a trip now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let startedAt = coordinator.trackingStartedAt {
                Text(startedAt, style: .timer)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var liveMap: some View {
        Map(position: $position) {
            UserAnnotation()
            if let trip = coordinator.recorder.currentTrip {
                let coordinates = trip.coordinates
                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(TripPalette.color(for: trip), lineWidth: 4)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
    }

    private var liveShareFooter: String {
        if settings.liveShareEndpoint.trimmingCharacters(in: .whitespaces).isEmpty {
            return "While tracking, your position and current song are paired into one feed. Add an HTTPS endpoint in Settings to publish it continuously, or use the share sheet to send a snapshot."
        }
        return "While tracking, your position and current song are posted to your endpoint every 10 seconds."
    }
}

/// Artwork, title, and a progress bar for the song being heard right now.
struct NowPlayingCard: View {
    let snapshot: NowPlayingSnapshot
    let listenedSeconds: Double

    private var fraction: Double {
        ListeningEvent.fraction(listened: listenedSeconds, duration: snapshot.durationSeconds ?? 0)
    }

    var body: some View {
        HStack(spacing: 14) {
            ArtworkThumbnail(url: snapshot.artworkURL, source: snapshot.source)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SourceBadge(source: snapshot.source)
                    Text(snapshot.source.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !snapshot.isPlaying {
                        Text("Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(snapshot.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let duration = snapshot.durationSeconds, duration > 0 {
                    ProgressView(value: fraction)
                        .tint(snapshot.source.tint)
                    Text("\(Formatters.clock(listenedSeconds)) heard of \(Formatters.clock(duration)) · \(Formatters.percent(fraction))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
