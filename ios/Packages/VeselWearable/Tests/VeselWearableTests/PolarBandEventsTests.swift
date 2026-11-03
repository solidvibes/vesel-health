import Foundation
@preconcurrency import PolarBleSdk
import SwiftProtobuf
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

    /// The exercise notice's state (field 1: running 1, paused 2, off 3) and its start time (field 4).
    @Test func exerciseNoticesStartAndEndAWorkout() throws {
        let now = at("2026-10-29T10:00:00Z")
        var start = PbLocalDateTime()
        start.date.year = 2026
        start.date.month = 10
        start.date.day = 29
        start.time.hour = 10
        start.time.minute = 58
        start.time.seconds = 0
        start.time.millis = 0
        start.timeZoneOffset = 60
        let startBytes: [UInt8] = try start.serializedBytes()
        func event(_ bytes: [UInt8]) -> BandEvent? {
            PolarBandEvents.event(.exerciseStatus, parameters: Data(bytes), at: now)
        }
        #expect(event([0x08, 0x01, 0x22, UInt8(startBytes.count)] + startBytes) == .workoutStarted(at: at("2026-10-29T09:58:00Z")))
        #expect(event([0x08, 0x01]) == .workoutStarted(at: now))
        #expect(event([0x08, 0x03]) == .workoutEnded(at: now))
        #expect(event([0x08, 0x02]) == .checkIn)
        #expect(event([0xFF]) == .checkIn)
    }
}
