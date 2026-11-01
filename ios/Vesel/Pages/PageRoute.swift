import SwiftUI
import VeselCore

/// A signal's page: the thing, the day it opens on and the period it opens in. A page gets its day here and never reads the shared day.
struct PageRoute: Hashable {
    let kind: PageKind
    let day: DayKey
    var period: PagePeriod = .day
}

/// Pushes a page on the stack the screen sits in: `@Environment(\.openPage) var openPage`, then `openPage(PageRoute(kind: .sleep, day: day))`.
struct OpenPage {
    let action: @MainActor (PageRoute) -> Void

    @MainActor func callAsFunction(_ route: PageRoute) { action(route) }
}

extension EnvironmentValues {
    @Entry var openPage = OpenPage(action: { _ in })
}

extension View {
    /// Registers the page on this stack.
    func pageDestinations(environment: AppEnvironment) -> some View {
        navigationDestination(for: PageRoute.self) { SignalPage(route: $0, environment: environment) }
    }
}
