import Foundation
import UIKit
import CoreLocation
import Combine

// MARK: - KeepAwakeMode
//
// How the app survives work that outlives the Auto-Lock timer.
//
//  • `.screen`            — holds `isIdleTimerDisabled` while a lease is open.
//                           The screen stays on, the app stays foreground.
//  • `.screenAndLocation` — the above, plus a deliberately *low-power*
//                           `CLLocationManager` session (three-kilometer
//                           accuracy, coarse distance filter, no heading, no
//                           visits). iOS keeps a foreground process with an
//                           active location session running, which is what lets
//                           a long local generation finish, and the local API
//                           node stay reachable on the LAN, while the screen is
//                           off. No coordinates are stored, logged, or sent.
//
// `.off` is the default: nothing is held and Auto-Lock behaves normally.

enum KeepAwakeMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case screen
    case screenAndLocation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:               return "Off"
        case .screen:            return "Keep screen on"
        case .screenAndLocation: return "Screen + background"
        }
    }

    var detail: String {
        switch self {
        case .off:               return "Auto-Lock behaves normally"
        case .screen:            return "Stays awake while the app is open"
        case .screenAndLocation: return "Also keeps running when the screen is off"
        }
    }

    var symbol: String {
        switch self {
        case .off:               return "moon.zzz"
        case .screen:            return "sun.max"
        case .screenAndLocation: return "location.circle"
        }
    }

    /// True when this mode needs the location keep-alive.
    var usesLocation: Bool { self == .screenAndLocation }
}

// MARK: - KeepAwakeService
//
// Single authority for the idle timer and the location keep-alive.
//
// Design invariants:
//  1. Leases, not flags. Any feature that needs the app alive takes a named
//     lease (`begin`/`end`) and releases it in a `defer`. The timer is on
//     exactly while at least one lease is open and the mode is not `.off`.
//  2. The local API server's existing "keep screen awake" preference is a
//     separate server lease, so turning keep-awake off never silently breaks
//     the server toggle, and vice versa.
//  3. Location is requested only when it will actually be used, and only
//     `whenInUse` — never Always. A missing `UIBackgroundModes: location`
//     entry leaves `allowsBackgroundLocationUpdates` at its default instead of
//     raising an exception.
//  4. Nothing about a coordinate ever leaves the object: the session exists
//     only to keep the process running.
@MainActor
final class KeepAwakeService: NSObject, ObservableObject {

    static let shared = KeepAwakeService()

    /// Lease names used by the built-in features. Free-form strings are fine;
    /// these exist so the UI can explain who is holding the app awake.
    enum Lease {
        static let localAPIServer = "local-api-server"
        static let generation = "generation"
        static let webBrowse = "web-browse"
    }

    @Published private(set) var activeLeases: Set<String> = []
    @Published private(set) var isHoldingAwake = false
    @Published private(set) var isKeepingLocationAlive = false
    @Published private(set) var locationStatus: CLAuthorizationStatus
    @Published private(set) var lastError: String?

    private let manager: CLLocationManager
    private var serverLeaseActive = false
    private var locationKeepAliveRunning = false

    private override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.locationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        // Coarse on purpose: three-kilometer accuracy uses far less power than
        // a navigation session and is all iOS needs to keep us resident.
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 500
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other

        // Both of these raise at runtime when the app does not declare the
        // `location` background mode. Check the built plist first.
        if Self.declaresLocationBackgroundMode {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
    }

    // MARK: - Stored preference

    var mode: KeepAwakeMode {
        KeepAwakeMode(rawValue: AppSettings.shared.keepAwakeMode) ?? .off
    }

    func setMode(_ mode: KeepAwakeMode) {
        AppSettings.shared.keepAwakeMode = mode.rawValue
        if mode.usesLocation,
           AppSettings.shared.keepAwakeLocationArmed,
           locationStatus == .notDetermined {
            // Ask once, at the moment the user asks for the feature.
            manager.requestWhenInUseAuthorization()
        }
        reconcile()
    }

    /// True when the user picked the background mode but iOS has not granted
    /// location yet. The UI shows an "Enable in iOS Settings" action then.
    var locationPermissionMissing: Bool {
        mode.usesLocation && !Self.isAuthorized(locationStatus)
    }

    var locationPermissionDenied: Bool {
        locationStatus == .denied || locationStatus == .restricted
    }

    func requestLocationAuthorization() {
        switch locationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // Only iOS Settings can undo a denial.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            reconcile()
        }
    }

    // MARK: - Leases

    func begin(_ lease: String) {
        guard activeLeases.insert(lease).inserted else { return }
        reconcile()
    }

    func end(_ lease: String) {
        guard activeLeases.remove(lease) != nil else { return }
        reconcile()
    }

    /// Ties a lease to a boolean state (server running, generation active).
    func setLease(_ lease: String, active: Bool) {
        active ? begin(lease) : end(lease)
    }

    /// The local API server's own "keep screen awake" preference.
    func setServerLease(active: Bool) {
        guard serverLeaseActive != active else { return }
        serverLeaseActive = active
        reconcile()
    }

    /// Wraps an async operation in a lease. Used by generation and by the
    /// browsing agent so a long job never loses the app mid-flight.
    func withLease<T>(_ lease: String, _ body: () async throws -> T) async rethrows -> T {
        begin(lease)
        defer { end(lease) }
        return try await body()
    }

    // MARK: - Derived state

    /// True when the process is meant to keep running in the background. The
    /// lifecycle controllers read this before tearing the local API server
    /// down on `.background`.
    var wantsBackgroundKeepAlive: Bool {
        guard mode.usesLocation,
              AppSettings.shared.keepAwakeLocationArmed,
              Self.isAuthorized(locationStatus) else { return false }
        return serverLeaseActive || !activeLeases.isEmpty
    }

    var statusLine: String {
        switch mode {
        case .off:
            return activeLeases.isEmpty ? "Unheld · Auto-Lock normal" : "Held idle"
        case .screen:
            return isHoldingAwake ? "Screen held on" : "Waiting for work"
        case .screenAndLocation:
            if locationPermissionMissing { return "Location permission needed" }
            return isKeepingLocationAlive ? "Awake · background keep-alive on" : "Waiting for work"
        }
    }

    // MARK: - Reconciliation

    /// Applies the current mode + leases to the idle timer and the location
    /// session. Idempotent: safe to call on every scene-phase change.
    func reconcile() {
        let sessionWantsAwake = !activeLeases.isEmpty && mode != .off
        let screenAwake = serverLeaseActive || sessionWantsAwake
        if UIApplication.shared.isIdleTimerDisabled != screenAwake {
            UIApplication.shared.isIdleTimerDisabled = screenAwake
        }
        if isHoldingAwake != screenAwake {
            isHoldingAwake = screenAwake
        }
        updateLocationKeepAlive(wanted: wantsBackgroundKeepAlive)
    }

    /// Releases everything transient. Called when the user turns keep-awake off
    /// or the app is about to be terminated by the system.
    func releaseAll() {
        activeLeases.removeAll()
        serverLeaseActive = false
        reconcile()
    }

    private func updateLocationKeepAlive(wanted: Bool) {
        guard wanted else {
            if locationKeepAliveRunning {
                manager.stopUpdatingLocation()
                locationKeepAliveRunning = false
                isKeepingLocationAlive = false
            }
            return
        }
        guard !locationKeepAliveRunning else { return }
        locationKeepAliveRunning = true
        isKeepingLocationAlive = true
        manager.startUpdatingLocation()
    }

    // MARK: - Helpers

    static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static var declaresLocationBackgroundMode: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?
            .contains("location") ?? false
    }

    fileprivate func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        locationStatus = status
        if !Self.isAuthorized(status) {
            lastError = status == .denied
                ? "Location access is off; the background keep-alive is unavailable."
                : nil
        } else {
            lastError = nil
        }
        reconcile()
    }
}

// MARK: - CLLocationManagerDelegate
//
// Delegate callbacks arrive on the main run loop because the manager was
// created on the main actor, but the conformance is still `nonisolated` so it
// does not depend on that ordering.

extension KeepAwakeService: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.handleAuthorizationChange(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Intentionally ignored: the session exists to keep the process
        // resident, not to learn where the device is.
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.lastError = message
        }
    }
}
