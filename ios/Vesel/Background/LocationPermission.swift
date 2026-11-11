import CoreLocation
import Observation

/// Whether Vesel may record a route. iOS is asked only when the owner taps Allow or turns Record my route on: While using
/// first, then Always. Opening a screen never asks.
@MainActor
@Observable
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case notAsked
        /// Routes start only while Vesel is open.
        case whileUsing
        case always
        /// Off for Vesel in iOS Settings, or not allowed on this phone.
        case off
    }

    private(set) var state: State
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private var askingAlways = false

    override init() {
        let manager = CLLocationManager()
        state = Self.state(manager.authorizationStatus)
        self.manager = manager
        super.init()
        manager.delegate = self
    }

    func ask() {
        switch manager.authorizationStatus {
        case .notDetermined:
            askingAlways = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// Whether a route may start now: always with Always, and with While using only while Vesel is open.
    static func canRecord(whileOpen: Bool) -> Bool {
        switch state(CLLocationManager().authorizationStatus) {
        case .always: true
        case .whileUsing: whileOpen
        case .notAsked, .off: false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // iOS calls the delegate on the thread that made the manager: the main thread.
        MainActor.assumeIsolated { changed(status) }
    }

    private func changed(_ status: CLAuthorizationStatus) {
        state = Self.state(status)
        guard askingAlways, status != .notDetermined else { return }
        askingAlways = false
        if status == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
    }

    private static func state(_ status: CLAuthorizationStatus) -> State {
        switch status {
        case .notDetermined: .notAsked
        case .authorizedWhenInUse: .whileUsing
        case .authorizedAlways: .always
        default: .off
        }
    }
}
