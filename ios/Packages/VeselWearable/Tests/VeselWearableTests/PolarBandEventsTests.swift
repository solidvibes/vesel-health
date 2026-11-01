import Foundation
@preconcurrency import PolarBleSdk
import Testing
@testable import VeselWearable

struct PolarBandEventsTests {
    let loop: PolarDeviceInfo = ("FAKE0001", UUID(), -60, "Polar Loop", true, true)

    /// With automatic reconnection the SDK goes from connected straight to connecting: that is a drop.
    @Test func reconnectingCountsAsADrop() {
        let events = PolarBandEvents(clock: TestClock("2026-10-29T10:00:00Z"))
        events.deviceConnecting(loop)
        events.deviceConnected(loop)
        #expect(events.drops == 0)

        events.deviceConnecting(loop)
        events.deviceConnected(loop)
        #expect(events.drops == 1)
    }

    /// Every connect brings the battery level and charging state once; each is a chance to read.
    @Test func batteryAndChargingAreCheckIns() async {
        let events = PolarBandEvents(clock: TestClock("2026-10-29T10:00:00Z"))
        events.deviceConnected(loop)
        events.batteryLevelReceived("FAKE0001", batteryLevel: 80)
        events.batteryChargingStatusReceived("FAKE0001", chargingStatus: .charging)
        var received: [BandEvent] = []
        for await event in events.stream {
            received.append(event)
            if received.count == 3 { break }
        }
        #expect(received == [.connected, .checkIn, .checkIn])
    }

    @Test func noticesThatWakeARead() {
        let now = at("2026-10-29T10:00:00Z")
        func event(_ type: PolarDeviceToHostNotification, _ bytes: [UInt8] = []) -> BandEvent? {
            PolarBandEvents.event(type, parameters: Data(bytes), at: now)
        }
        #expect(event(.syncRequired) == .syncRequested)
        #expect(event(.exerciseStatus) == .checkIn)
        #expect(event(.restApiEvent) == nil)
        #expect(event(.inactivityAlert, [0x08, 0x00]) == .stillTooLong(at: now))
        #expect(event(.inactivityAlert) == .stillTooLong(at: now))
        #expect(event(.inactivityAlert, [0x08, 0x05]) == .checkIn)
        #expect(event(.inactivityAlert, [0x08]) == .checkIn)
    }
}
