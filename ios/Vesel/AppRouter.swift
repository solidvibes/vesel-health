import Foundation
import Observation
import VeselCore

/// Where a notification or a widget tap takes the tabs.
@MainActor
@Observable
final class AppRouter {
    /// Set each time a notification or a widget is tapped; the tabs go there.
    private(set) var tabRequest: TabRequest?
    private let clock: any VeselClock

    init(clock: any VeselClock) {
        self.clock = clock
    }

    /// A notification was tapped: the morning report opens its night's Sleep page; anything else opens Today.
    func openNotification(_ identifier: String) {
        if let (kind, day) = AlertIdentifier.parse(identifier), kind == .morningReport {
            open(.today, page: PageRoute(kind: .sleep, day: day))
        } else {
            open(.today)
        }
    }

    /// A widget was tapped: `vesel://today` opens Today; `vesel://recovery`, `vesel://sleep` and `vesel://stress` open that page for today over it.
    func open(_ url: URL) {
        guard url.scheme == "vesel", let host = url.host() else { return }
        let today = clock.today
        switch host {
        case "today": open(.today)
        case "recovery": open(.today, page: PageRoute(kind: .recovery, day: today))
        case "sleep": open(.today, page: PageRoute(kind: .sleep, day: today))
        case "stress": open(.today, page: PageRoute(kind: .stress, day: today))
        default: break
        }
    }

    private func open(_ tab: AppTab, page: PageRoute? = nil) {
        tabRequest = TabRequest(tab: tab, page: page, serial: (tabRequest?.serial ?? 0) + 1)
    }
}

/// A tab to go to, with a page pushed on it. `serial` makes a second tap on the same tab a new request.
struct TabRequest: Equatable {
    var tab: AppTab
    var page: PageRoute?
    var serial: Int
}
