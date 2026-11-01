import CoreBluetooth
import Foundation
@preconcurrency import PolarBleSdk
import VeselCore

/// Connection changes and the band's own notices, from the SDK, which calls back on its own queue. Nothing is dropped:
/// events are tiny and the app handles them one at a time.
final class PolarBandEvents: PolarBleApiObserver, PolarBleApiDeviceInfoObserver, PolarBleApiPowerStateObserver, @unchecked Sendable {
    let stream: AsyncStream<BandEvent>
    private let continuation: AsyncStream<BandEvent>.Continuation
    let links: AsyncStream<BandLink>
    private let linkContinuation: AsyncStream<BandLink>.Continuation
    private let clock: any VeselClock
    private let lock = NSLock()
    private var _state: ConnectionState = .disconnected
    private var _pairingRefused = false
    private var _drops = 0
    private var watching: [Task<Void, Never>] = []

    init(clock: any VeselClock) {
        self.clock = clock
        (stream, continuation) = AsyncStream.makeStream()
        (links, linkContinuation) = AsyncStream.makeStream()
    }

    var state: ConnectionState { lock.withLock { _state } }
    var pairingRefused: Bool { lock.withLock { _pairingRefused } }
    var drops: Int { lock.withLock { _drops } }

    private static let addressKey = "vesel.loopBluetoothAddress"

    /// The Loop's iOS Bluetooth address from its last connection. A link iOS restores after relaunching Vesel is known to
    /// the SDK only by this address, not by the Loop's Polar ID.
    var address: String? { UserDefaults.standard.string(forKey: Self.addressKey) }

    func reset() {
        lock.withLock { _pairingRefused = false }
    }

    /// Subscribes to the end of sleep recording and to the band's notices. Returns once the sleep
    /// subscription has answered (it reads and writes band files), so it doesn't overlap the next SDK call.
    func watch(_ api: PolarBleApi, deviceId: String, timeout: Duration) async {
        stopWatching()
        let (subscribed, signal) = AsyncStream<Void>.makeStream()
        let sleep = Task { [continuation] in
            var recording: Bool?
            do {
                for try await statuses in api.observeSleepRecordingStatus(identifier: deviceId) {
                    signal.yield()
                    switch statuses.last {
                    case .enabled: recording = true
                    case .disabled:
                        if recording == true { continuation.yield(.sleepEnded) }
                        recording = false
                    case .unknown, nil: break
                    }
                }
            } catch {}
            signal.finish()
        }
        let notices = Task { [continuation, clock] in
            do {
                for try await notice in api.observeDeviceToHostNotifications(identifier: deviceId) {
                    if let event = Self.event(notice.notificationType, parameters: notice.parameters, at: clock.now) {
                        continuation.yield(event)
                    }
                }
            } catch {}
        }
        lock.withLock { watching = [sleep, notices] }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in subscribed { return } }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    /// `restApiEvent` is left out: it is the sleep-state notice `observeSleepRecordingStatus` already turns into `.sleepEnded`.
    /// Only an inactivity alert that fired (countdown 0) is `.stillTooLong`; the warning before it, or one that can't be
    /// read, only checks in.
    static func event(_ type: PolarDeviceToHostNotification, parameters: Data, at now: Date) -> BandEvent? {
        switch type {
        case .syncRequired: .syncRequested
        case .inactivityAlert: PolarMapping.inactivityCountdown(parameters) == 0 ? .stillTooLong(at: now) : .checkIn
        case .exerciseStatus: .checkIn
        default: nil
        }
    }

    private func stopWatching() {
        let tasks = lock.withLock {
            defer { watching = [] }
            return watching
        }
        tasks.forEach { $0.cancel() }
    }

    /// With automatic reconnection, the SDK reports a dropped connection only as connecting again, not as disconnected.
    func deviceConnecting(_ identifier: PolarDeviceInfo) {
        lock.withLock {
            if _state == .connected { _drops += 1 }
            _state = .connecting
        }
        linkContinuation.yield(BandLink(at: clock.now, event: .connecting))
    }

    func deviceConnected(_ identifier: PolarDeviceInfo) {
        lock.withLock { _state = .connected }
        UserDefaults.standard.set(identifier.address.uuidString, forKey: Self.addressKey)
        linkContinuation.yield(BandLink(at: clock.now, event: .connected))
        continuation.yield(.connected)
    }

    func deviceDisconnected(_ identifier: PolarDeviceInfo, info: PolarBleDisconnectInfo) {
        let refused = [.insufficientEncryption, .encryptionTimedOut, .pairingInformationRemoved, .pairingNegotiationFailed, .uuidNotAllowed]
            .contains(info.reason)
        lock.withLock {
            _state = .disconnected
            _drops += 1
            if refused { _pairingRefused = true }
        }
        linkContinuation.yield(BandLink(at: clock.now, event: .disconnected, reason: String(describing: info.reason)))
        stopWatching()
    }

    func blePowerOn() {
        linkContinuation.yield(BandLink(at: clock.now, event: .bluetoothOn))
    }

    func blePowerOff() {
        linkContinuation.yield(BandLink(at: clock.now, event: .bluetoothOff))
    }

    func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
        continuation.yield(.checkIn)
    }

    func batteryChargingStatusReceived(_ identifier: String, chargingStatus: BleBasClient.ChargeState) {
        continuation.yield(.checkIn)
    }

    func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {}

    func disInformationReceivedWithKeysAsStrings(_ identifier: String, key: String, value: String) {}
}
