import SwiftUI
import MapKit
import CoreLocation

/// A full-screen map of the trip in progress, with a Begin/End trip control at the bottom
/// and a bubble at the top naming whatever is playing right now.
struct LiveView: View {
    @Environment(TrackingCoordinator.self) private var coordinator
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
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
            MapCompass()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let snapshot = coordinator.listening.current {
                NowPlayingBubble(snapshot: snapshot)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controlPanel
        }
        .appTabBarInset()
        .animation(.snappy, value: coordinator.listening.current?.trackID)
        .animation(.snappy, value: coordinator.isTracking)
    }

    // MARK: - Bottom panel

    private var controlPanel: some View {
        VStack(spacing: 12) {
            Button {
                coordinator.toggleManualTracking()
            } label: {
                Label(
                    coordinator.isTracking ? "End trip" : "Begin trip",
                    systemImage: coordinator.isTracking ? "stop.circle.fill" : "record.circle"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(coordinator.isTracking ? .red : .accentColor)

            if coordinator.location.authorizationDenied {
                Label("Location access is denied. Enable it in Settings.", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if coordinator.location.accuracyLimited {
                Label("Precise Location is off; paths will be approximate.", systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

/// Artwork, title, and artist of the song playing right now.
private struct NowPlayingBubble: View {
    let snapshot: NowPlayingSnapshot

    var body: some View {
        HStack(spacing: 10) {
            ArtworkThumbnail(url: snapshot.artworkURL, source: snapshot.source)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(snapshot.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !snapshot.isPlaying {
                Image(systemName: "pause.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Paused")
            }
            SourceBadge(source: snapshot.source)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now playing \(snapshot.title) by \(snapshot.artist) on \(snapshot.source.displayName)")
    }
}
