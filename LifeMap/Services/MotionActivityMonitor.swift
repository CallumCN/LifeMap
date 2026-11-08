import Foundation
import CoreLocation
import Observation
#if canImport(CoreMotion)
import CoreMotion
#endif

/// Watches Core Motion's activity classifier and reports which `MotionActivityKind`
/// the user is currently doing. Train travel is not a Core Motion class, so it is
/// inferred: the device is moving fast (via low-power significant-change location)
/// while Core Motion does not report walking, running, or cycling.
@Observable
final class MotionActivityMonitor: NSObject {
    private(set) var current: MotionActivityKind?
    private(set) var isAvailable = false
    private(set) var isRunning = false

    /// Fires whenever the classified activity changes (including to `nil` for stationary/unknown).
    var onChange: ((MotionActivityKind?) -> Void)?

    #if os(iOS)
    private let activityManager = CMMotionActivityManager()
    #endif
    private let significantChangeManager = CLLocationManager()
    private var lastSignificantLocation: CLLocation?
    private var rawMotionActivity: MotionActivityKind?
    private var trainDetectionEnabled = false

    /// Speed above which non-pedestrian, non-cycling movement is treated as a train.
    private static let trainSpeedThreshold: CLLocationSpeed = 12

    override init() {
        super.init()
        #if os(iOS)
        isAvailable = CMMotionActivityManager.isActivityAvailable()
        #endif
        significantChangeManager.delegate = self
    }

    func start(detectTrains: Bool) {
        guard !isRunning else { return }
        isRunning = true
        trainDetectionEnabled = detectTrains
        #if os(iOS)
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            Task { @MainActor in
                self?.handle(activity)
            }
        }
        #endif
        if detectTrains, CLLocationManager.significantLocationChangeMonitoringAvailable() {
            significantChangeManager.startMonitoringSignificantLocationChanges()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        #if os(iOS)
        activityManager.stopActivityUpdates()
        #endif
        significantChangeManager.stopMonitoringSignificantLocationChanges()
        update(to: nil)
    }

    #if os(iOS)
    private func handle(_ activity: CMMotionActivity?) {
        guard let activity else { return }
        // Confidence filtering avoids flapping on low-confidence guesses.
        guard activity.confidence != .low else { return }
        let kind: MotionActivityKind?
        if activity.automotive {
            kind = .automotive
        } else if activity.cycling {
            kind = .cycling
        } else if activity.running {
            kind = .running
        } else if activity.walking {
            kind = .walking
        } else {
            kind = nil
        }
        rawMotionActivity = kind
        // A train ride can look like "unknown" to Core Motion; keep the inferred train
        // state unless Core Motion now says the user is clearly on foot or cycling.
        if current == .train, kind == nil || kind == .automotive {
            return
        }
        update(to: kind)
    }
    #endif

    private func handleSignificantLocation(_ location: CLLocation) {
        defer { lastSignificantLocation = location }
        guard trainDetectionEnabled else { return }
        var speed = location.speed
        if speed < 0, let previous = lastSignificantLocation {
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            if seconds > 0 {
                speed = location.distance(from: previous) / seconds
            }
        }
        let onFoot = rawMotionActivity == .walking || rawMotionActivity == .running || rawMotionActivity == .cycling
        if speed >= Self.trainSpeedThreshold, !onFoot {
            update(to: .train)
        } else if current == .train, speed >= 0, speed < 2 {
            update(to: rawMotionActivity)
        }
    }

    private func update(to kind: MotionActivityKind?) {
        guard kind != current else { return }
        current = kind
        onChange?(kind)
    }
}

extension MotionActivityMonitor: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handleSignificantLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Significant-change failures are non-fatal; the activity classifier still works.
    }
}
