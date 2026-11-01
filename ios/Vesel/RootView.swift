import SwiftUI
import UIKit
import VeselCore

enum AppTab: String, CaseIterable {
    case today, journal, body
    /// The ring at the end of the tab bar. It is never a page: choosing it opens Loop & settings.
    case loop

    /// The Simulator can open on a tab with `-VeselTab <name>`.
    init(defaults: UserDefaults) {
        let named = defaults.string(forKey: "VeselTab").flatMap(AppTab.init(rawValue:))
        self = named == .loop ? .today : named ?? .today
    }
}

/// Pairing until a Loop is paired, then the three tabs.
struct RootView: View {
    let environment: AppEnvironment
    let router: AppRouter

    var body: some View {
        switch environment.isPaired {
        case .none: BlobBackground()
        case .some(false): PairingFlow(environment: environment)
        case .some(true): MainTabs(environment: environment, router: router)
        }
    }
}

private struct MainTabs: View {
    let environment: AppEnvironment
    let router: AppRouter
    @State private var selection: AppTab
    @State private var todayPath: NavigationPath
    @State private var journalPath: NavigationPath
    @State private var bodyPath: NavigationPath
    @State private var meaning: MeaningRequest?
    @State private var readingCard: ReadingCardGate
    @State private var root: RootModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, router: AppRouter) {
        self.environment = environment
        self.router = router
        let launch = environment.launch
        let request = router.tabRequest
        let tab = request?.tab ?? launch.tab
        _selection = State(initialValue: tab)
        _readingCard = State(initialValue: ReadingCardGate(isReading: environment.status.sync.isReading))
        _root = State(initialValue: RootModel(database: environment.database, clock: environment.clock, days: environment.days))
        var today = NavigationPath()
        if launch.opensLoopSettings { today.append(TodayRoute.loopSettings) }
        if launch.opensSyncing { today.append(TodayRoute.syncing) }
        if launch.opensMeanings { today.append(TodayRoute.meanings) }
        #if DEBUG
        if launch.opensBandDataReport { today.append(TodayRoute.bandDataReport) }
        #endif
        if let page = request?.page { today.append(page) }
        var journal = NavigationPath()
        var bodyTab = NavigationPath()
        if request == nil {
            switch tab {
            case .today, .loop: launch.routes(day: environment.clock.today).forEach { today.append($0) }
            case .journal: launch.routes(day: environment.days.day).forEach { journal.append($0) }
            case .body: launch.routes(day: environment.clock.today).forEach { bodyTab.append($0) }
            }
        }
        _todayPath = State(initialValue: today)
        _journalPath = State(initialValue: journal)
        _bodyPath = State(initialValue: bodyTab)
        _meaning = State(initialValue: launch.meaning.map { MeaningRequest(term: $0) })
    }

    private var isReading: Bool { environment.status.sync.isReading }
    private var isActive: Bool { scenePhase == .active }
    private var batteryLow: Bool { root.batteryLow }

    private var ringValue: String {
        switch (isReading, batteryLow) {
        case (true, true): "Reading, battery low"
        case (true, false): "Reading"
        case (false, true): "Battery low"
        case (false, false): ""
        }
    }

    private func openLoopSettings() {
        selection = .today
        todayPath = NavigationPath([TodayRoute.loopSettings])
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack(path: $todayPath) {
                    TodayView(
                        environment: environment, readingCard: readingCard, openPage: { todayPath.append($0) },
                        openSyncing: { todayPath.append(TodayRoute.syncing) }
                    )
                    .navigationDestination(for: TodayRoute.self) { route in
                        switch route {
                        case .loopSettings: LoopSettingsView(environment: environment)
                        case .syncing: SyncingView(environment: environment)
                        case .meanings: WhatThingsMeanView()
                        #if DEBUG
                        case .bandDataReport: BandDataReportView(environment: environment)
                        #endif
                        }
                    }
                    .pageDestinations(environment: environment)
                    .toolbarVisibility(.hidden, for: .navigationBar)
                }
                .environment(\.openPage, OpenPage { todayPath.append($0) })
            }
            Tab("Journal", systemImage: "book.closed", value: AppTab.journal) {
                NavigationStack(path: $journalPath) {
                    JournalView(environment: environment)
                        .pageDestinations(environment: environment)
                        .toolbarVisibility(.hidden, for: .navigationBar)
                }
                .environment(\.openPage, OpenPage { journalPath.append($0) })
            }
            Tab("Body", systemImage: "waveform.path.ecg.rectangle", value: AppTab.body) {
                NavigationStack(path: $bodyPath) {
                    BodyView(environment: environment)
                        .pageDestinations(environment: environment)
                        .toolbarVisibility(.hidden, for: .navigationBar)
                }
                .environment(\.openPage, OpenPage { bodyPath.append($0) })
            }
            Tab(value: AppTab.loop, role: .search) {
                Color.clear
            } label: {
                Label {
                    Text("Loop and settings")
                } icon: {
                    Image(uiImage: LoopRing.image(reading: isReading && isActive, reduceMotion: reduceMotion, low: batteryLow))
                }
                .accessibilityValue(ringValue)
            }
        }
        .tint(Theme.Palette.primary)
        .onChange(of: selection) { _, new in
            if new == .loop { openLoopSettings() }
        }
        .onChange(of: scenePhase) { old, new in
            if old == .background && new == .active { readingCard.cameToForeground(isReading: isReading) }
        }
        .onChange(of: isReading) { _, reading in
            let wasShown = readingCard.isShown
            readingCard.readingChanged(reading)
            if wasShown && !reading { AccessibilityNotification.Announcement("Reading done").post() }
        }
        .task(id: readingCard.isWaiting && isActive) {
            guard readingCard.isWaiting, isActive else { return }
            try? await Task.sleep(for: ReadingCardGate.delay)
            guard !Task.isCancelled else { return }
            readingCard.delayPassed()
        }
        .environment(\.showMeaning, ShowMeaning { meaning = $0 })
        .environment(\.openURL, TermLink.action { meaning = $0 })
        .sheet(item: $meaning) { MeaningSheet(request: $0) }
        .task(id: isActive) {
            guard isActive else { return }
            await root.observeFirstDay()
        }
        .task(id: isActive) {
            guard isActive else { return }
            await root.observeBattery()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            environment.days.clockChanged()
        }
        .onChange(of: router.tabRequest) {
            guard let request = router.tabRequest else { return }
            selection = request.tab
            if request.tab == .today {
                todayPath = NavigationPath()
                if let page = request.page { todayPath.append(page) }
            }
        }
    }
}

enum TodayRoute: Hashable {
    case loopSettings
    case syncing
    case meanings
    #if DEBUG
    case bandDataReport
    #endif
}
