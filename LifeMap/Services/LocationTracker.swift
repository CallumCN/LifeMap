import Foundation
import CoreLocation
import Observation

/// Streams high-precision location fixes while a trip is being recorded.
///
/// Uses the async `CLLocationUpdate.liveUpdates` API, a `CLServiceSession` to hold
/// Always authorization, and (on iOS) a `CLBackgroundActivitySession` so updates keep
/// arriving after the app leaves the foreground.
@Observable
final class LocationTracker {
    private(set) var isRunning = false
    private(set) var latestLocation: CLLocation?
    private(set) var authorizationDenied = false
    private(set) var accuracyLimited = false
    private(set) var lastError: String?

    /// Called for each accepted location fix.
    var onLocation: ((CLLocation) -> Void)?

    private var updatesTask: Task<Void, Never>?
    private var serviceSession: CLServiceSession?
    #if os(iOS)
    private var backgroundSession: CLBackgroundActivitySession?
    #endif

    /// Hold an Always-authorization session for the life of the app so the system can
    /// relaunch us in the background. Call once at launch when always-on or motion
    /// tracking is enabled.
    func holdAlwaysAuthorization() {
        if serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .always)
        }
    }

    func releaseAlwaysAuthorization() {
        serviceSession?.invalidate()
        serviceSession = nil
    }

    /// Picks the Core Location configuration that best fits the activity being recorded.
    static func configuration(for activity: MotionActivityKind?, highPrecision: Bool) -> CLLocationUpdate.LiveConfiguration {
        switch activity {
        case .automotive:
            return .automotiveNavigation
        case .cycling, .train:
            return .otherNavigation
        case .walking, .running:
            return highPrecision ? .otherNavigation : .fitness
        case nil:
            return highPrecision ? .otherNavigation : .default
        }
    }

    func start(configuration: CLLocationUpdate.LiveConfiguration) {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        holdAlwaysAuthorization()
        #if os(iOS)
        backgroundSession = CLBackgroundActivitySession()
        #endif

        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(configuration) {
                    guard let self, !Task.isCancelled else { break }
                    self.authorizationDenied = update.authorizationDenied || update.authorizationDeniedGlobally
                    self.accuracyLimited = update.accuracyLimited
                    if let location = update.location, Self.isUsable(location) {
                        self.latestLocation = location
                        self.onLocation?(location)
                    }
                }
            } catch {
                self?.lastError = error.localizedDescription
            }
            self?.isRunning = false
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        #if os(iOS)
        backgroundSession?.invalidate()
        backgroundSession = nil
        #endif
        isRunning = false
    }

    /// Rejects fixes that are stale or too imprecise to draw a clean path.
    private static func isUsable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 65
            && abs(location.timestamp.timeIntervalSinceNow) < 30
    }
}
