import Foundation
import Testing
@testable import VeselStorage
import VeselCore

struct LedgerTests {
    let day = DayKey(year: 2026, month: 10, day: 20)

    func heartRates(_ bpm: Int...) -> BandPayload {
        let samples = bpm.enumerated().map { index, value in
            #"{"hr":\#(value),"time":"06:0\#(index):00","triggerType":"TIMED"}"#
        }
        return BandPayload(
            day: day, kind: .heartRate, json: #"{"date":"2026-10-20","samples":[\#(samples.joined(separator: ","))]}"#, utcOffsetSeconds: 7200,
            sampleCount: bpm.count)
    }

    @Test func emptyRefetchNeverReplacesStoredData() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save([heartRates(52, 54)], fetchedAt: at("2026-10-21T07:00:00Z"))
        try await database.markDeletedFromBand(.heartRate, through: day, at: at("2026-10-22T07:00:00Z"))

        try await database.save([.empty(day: day, kind: .heartRate, utcOffsetSeconds: 7200)], fetchedAt: at("2026-10-23T07:00:00Z"))

        let ledger = try await database.ledger([.heartRate])
        #expect(ledger.map(\.sampleCount) == [2])
        #expect(ledger.first?.storedAt == at("2026-10-21T07:00:00Z"))
        #expect(ledger.first?.deletedFromBandAt == at("2026-10-22T07:00:00Z"))
        let json = try await database.writer.read { try String.fetchOne($0, sql: "SELECT json FROM raw_export WHERE kind = 'heartRate'") }
        #expect(json == heartRates(52, 54).json)
        #expect(try await database.count("hr_sample") == 2)
    }

    @Test func emptyDayIsRecordedWhenNothingWasStored() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save([.empty(day: day, kind: .heartRate, utcOffsetSeconds: 7200)], fetchedAt: at("2026-10-21T07:00:00Z"))
        try await database.save([.empty(day: day, kind: .heartRate, utcOffsetSeconds: 7200)], fetchedAt: at("2026-10-22T07:00:00Z"))
        let ledger = try await database.ledger([.heartRate])
        #expect(ledger.map(\.sampleCount) == [0])
        #expect(ledger.first?.storedAt == at("2026-10-22T07:00:00Z"))
        #expect(ledger.first?.earlierEmptyAt == at("2026-10-21T07:00:00Z"))
        try await database.markDeletedFromBand(.heartRate, through: day, at: at("2026-10-22T07:01:00Z"))
        #expect(try await database.ledger([.heartRate]).first?.deletedFromBandAt == at("2026-10-22T07:01:00Z"))
    }

    @Test func onlyBackToBackEmptyReadsAreRemembered() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save([.empty(day: day, kind: .heartRate, utcOffsetSeconds: 7200)], fetchedAt: at("2026-10-20T07:00:00Z"))
        #expect(try await database.ledger([.heartRate]).first?.earlierEmptyAt == nil)
        try await database.save([heartRates(52)], fetchedAt: at("2026-10-21T07:00:00Z"))
        #expect(try await database.ledger([.heartRate]).first?.earlierEmptyAt == nil)
    }

    @Test func payloadIsStoredAsTypedRows() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save([heartRates(52, 54)], fetchedAt: at("2026-10-21T07:00:00Z"))
        let samples = try await database.heartRates(from: at("2026-10-20T00:00:00Z"), to: at("2026-10-21T00:00:00Z"))
        #expect(
            samples == [
                HeartRateSample(time: at("2026-10-20T04:00:00Z"), bpm: 52, trigger: .timed),
                HeartRateSample(time: at("2026-10-20T04:01:00Z"), bpm: 54, trigger: .timed),
            ])
    }

    @Test func readingsAloneLeaveTheLedgerToALaterSave() async throws {
        let database = try AppDatabase.inMemory()
        try await database.saveReadings([heartRates(52), .empty(day: day.adding(days: 1), kind: .heartRate, utcOffsetSeconds: 7200)])
        #expect(try await database.count("hr_sample") == 1)
        #expect(try await database.count("band_ledger") == 0)
        #expect(try await database.count("raw_export") == 0)

        try await database.save([heartRates(52, 54)], fetchedAt: at("2026-10-21T07:00:00Z"))
        #expect(try await database.count("hr_sample") == 2)
        #expect(try await database.ledger([.heartRate]).map(\.sampleCount) == [2])
        #expect(try await database.count("raw_export") == 1)
    }

    @Test func unreadableDayStoresNothing() async throws {
        let database = try AppDatabase.inMemory()
        let broken = BandPayload(day: day, kind: .sleep, json: #"{"oops":1}"#, utcOffsetSeconds: 7200, sampleCount: 3)
        await #expect(throws: BandPayloadError.unreadable(.sleep, day)) {
            try await database.save([heartRates(52), broken], fetchedAt: at("2026-10-21T07:00:00Z"))
        }
        #expect(try await database.count("band_ledger") == 0)
        #expect(try await database.count("hr_sample") == 0)
    }

    @Test func lastStoredDayIsPerKind() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save([heartRates(52)], fetchedAt: at("2026-10-21T07:00:00Z"))
        try await database.save([.empty(day: day.adding(days: 2), kind: .ppi, utcOffsetSeconds: 7200)], fetchedAt: at("2026-10-23T07:00:00Z"))
        #expect(try await database.lastStoredDay(.heartRate) == day)
        #expect(try await database.lastStoredDay(.ppi) == day.adding(days: 2))
        #expect(try await database.lastStoredDay(.sleep) == nil)
    }

    @Test func forgettingTheBandKeepsHistory() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(BandInfo(deviceId: "A1B2", name: "Polar Loop", pairedAt: at("2026-10-01T08:00:00Z")))
        try await database.save([heartRates(52)], fetchedAt: at("2026-10-21T07:00:00Z"))
        try await database.setSettings([AppDatabase.sleepStatusKey: "stopped"])
        try await database.forgetBand(at: at("2026-10-22T07:00:00Z"))
        #expect(try await database.band() == nil)
        // What the old Loop said about sleep never stops a read of the next one.
        #expect(try await database.setting(AppDatabase.sleepStatusKey) == nil)
        #expect(try await database.count("hr_sample") == 1)
        // The factory reset wiped the band, so a new Loop's clearing starts after these days.
        #expect(try await database.ledger([.heartRate]).first?.deletedFromBandAt == at("2026-10-22T07:00:00Z"))
    }

    @Test func lastSuccessfulSyncSkipsFailedRuns() async throws {
        let database = try AppDatabase.inMemory()
        let ok = try await database.startSyncRun(.manual, at: at("2026-10-21T07:00:00Z"))
        try await database.finishSyncRun(ok, outcome: .success, detail: nil, at: at("2026-10-21T07:01:00Z"))
        let failed = try await database.startSyncRun(.manual, at: at("2026-10-21T09:00:00Z"))
        try await database.finishSyncRun(failed, outcome: .unreachable, detail: nil, at: at("2026-10-21T09:00:05Z"))
        #expect(try await database.lastSuccessfulSync() == at("2026-10-21T07:01:00Z"))
    }
}
