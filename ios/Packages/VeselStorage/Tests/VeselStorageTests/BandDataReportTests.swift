import Foundation
import Testing
import VeselCore
import VeselStorage

struct BandDataReportTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!

    func session(_ iso: String, flags: [Bool]) -> PPISession {
        let start = at(iso)
        return PPISession(
            start: start,
            trigger: .automatic,
            utcOffsetSeconds: 3600,
            samples: flags.enumerated().map { index, flagged in
                PPISample(time: start.addingTimeInterval(Double(index)), intervalMs: 1000, errorMs: 10, blocker: flagged, skinContact: true)
            }
        )
    }

    @Test func countsPerLocalHour() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(session("2026-10-26T06:05:00Z", flags: [false, false, true, false]))
        try await database.save(session("2026-10-26T06:40:00Z", flags: [false, false]))
        try await database.save(session("2026-10-26T09:00:00Z", flags: [true]))
        try await database.save(heartRates: [
            HeartRateSample(time: at("2026-10-26T06:00:00Z"), bpm: 60, trigger: .timed),
            HeartRateSample(time: at("2026-10-26T06:05:00Z"), bpm: 61, trigger: .timed),
            HeartRateSample(time: at("2026-10-25T21:55:00Z"), bpm: 58, trigger: .timed),
        ])

        let report = try await database.bandDataReport(
            from: DayKey(year: 2026, month: 10, day: 26),
            through: DayKey(year: 2026, month: 10, day: 26),
            timeZone: berlin
        )

        let day = DayKey(year: 2026, month: 10, day: 26)
        #expect(
            report == [
                BandDataHour(day: day, hour: 7, ppiSessions: 2, ppiIntervals: 6, ppiFlagged: 1, hrSamples: 2),
                BandDataHour(day: day, hour: 10, ppiSessions: 1, ppiIntervals: 1, ppiFlagged: 1, hrSamples: 0),
            ])
    }
}
