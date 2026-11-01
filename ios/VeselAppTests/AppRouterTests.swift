import Foundation
import Testing
import VeselCore
@testable import Vesel

/// Widget links and notification taps: which tab and page they open.
@MainActor
struct AppRouterTests {
    let clock = FixedClock(now: try! Date("2026-10-25T13:00:00Z", strategy: .iso8601), timeZone: .gmt)
    let today = DayKey(year: 2026, month: 10, day: 25)

    func opened(_ link: String) -> TabRequest? {
        let router = AppRouter(clock: clock)
        router.open(URL(string: link)!)
        return router.tabRequest
    }

    @Test func eachLinkOpensItsTabAndPage() {
        #expect(opened("vesel://today") == TabRequest(tab: .today, page: nil, serial: 1))
        #expect(opened("vesel://recovery") == TabRequest(tab: .today, page: PageRoute(kind: .recovery, day: today), serial: 1))
        #expect(opened("vesel://sleep") == TabRequest(tab: .today, page: PageRoute(kind: .sleep, day: today), serial: 1))
        #expect(opened("vesel://stress") == TabRequest(tab: .today, page: PageRoute(kind: .stress, day: today), serial: 1))
    }

    @Test func unknownLinksOpenNothing() {
        #expect(opened("vesel://elsewhere") == nil)
        #expect(opened("https://today") == nil)
    }

    func tapped(_ identifier: String) -> TabRequest? {
        let router = AppRouter(clock: clock)
        router.openNotification(identifier)
        return router.tabRequest
    }

    @Test func theMorningReportOpensItsNightsSleepPage() {
        let night = DayKey(year: 2026, month: 10, day: 24)
        #expect(tapped(AlertIdentifier.make(.morningReport, night)) == TabRequest(tab: .today, page: PageRoute(kind: .sleep, day: night), serial: 1))
    }

    @Test func everyOtherNotificationOpensToday() {
        #expect(tapped(AlertIdentifier.make(.lowRecovery, today)) == TabRequest(tab: .today, page: nil, serial: 1))
        #expect(tapped(AlertIdentifier.make(.longHighStress, today)) == TabRequest(tab: .today, page: nil, serial: 1))
        #expect(tapped(AlertIdentifier.make(.unusualRestingHeartRate, today)) == TabRequest(tab: .today, page: nil, serial: 1))
        #expect(tapped("alert.standUp") == TabRequest(tab: .today, page: nil, serial: 1))
        #expect(tapped("something else") == TabRequest(tab: .today, page: nil, serial: 1))
    }

    @Test func aSecondTapIsANewRequest() {
        let router = AppRouter(clock: clock)
        router.openNotification("alert.standUp")
        router.openNotification("alert.standUp")
        #expect(router.tabRequest == TabRequest(tab: .today, page: nil, serial: 2))
    }
}
