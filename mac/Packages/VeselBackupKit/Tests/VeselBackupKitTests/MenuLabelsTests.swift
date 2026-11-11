import Foundation
import Testing
import VeselBackupKit

struct MenuLabelsTests {
    @Test func knownTablesInOrderAndTheRestSummed() {
        let lines = MenuLabels.lines(for: [
            "hr_sample": 1200, "sleep_night": 30, "profile": 1, "raw_export": 60, "alert_event": 0, "computed_metric": 90,
        ])
        #expect(
            lines == [
                CountLine(label: "nights of sleep", count: 30),
                CountLine(label: "heart-rate readings", count: 1200),
                CountLine(label: "other rows", count: 151),
            ])
    }

    @Test func workoutsAndRoutesHaveTheirOwnLines() {
        let lines = MenuLabels.lines(for: ["workout_route": 2, "workout": 3, "workout_file": 9, "workout_choice": 1])
        #expect(
            lines == [
                CountLine(label: "workouts", count: 3),
                CountLine(label: "workout routes", count: 2),
                CountLine(label: "other rows", count: 10),
            ])
    }

    @Test func nothingMeansNoLines() {
        #expect(MenuLabels.lines(for: [:]).isEmpty)
    }

    @Test func lastBackupIsRelative() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        calendar.locale = Locale(identifier: "en_GB")
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 21)))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 7, minute: 42)))
        let lastNight = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23, minute: 10)))
        let earlier = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 7, minute: 5)))
        #expect(MenuLabels.lastBackup(morning, now: now, calendar: calendar) == "today 07:42")
        #expect(MenuLabels.lastBackup(lastNight, now: now, calendar: calendar) == "yesterday 23:10")
        #expect(MenuLabels.lastBackup(earlier, now: now, calendar: calendar) == "3 Oct 07:05")
    }
}
