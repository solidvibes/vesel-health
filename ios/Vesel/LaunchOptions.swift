import Foundation
import VeselCore
import VeselStorage

/// Launch arguments that open the app on a given screen, for Simulator screenshots. On a device only the tab applies.
struct LaunchOptions {
    var tab: AppTab
    /// `-VeselScreen loop` opens Loop & settings; `-VeselScreen report` the band data report on top of it;
    /// `-VeselScreen aboutYou` the About you editor on Body; `-VeselScreen syncing` the Syncing page on top of it;
    /// `-VeselScreen meanings` the What things mean list on top of it.
    var opensLoopSettings: Bool
    var opensSyncing: Bool
    var opensMeanings: Bool
    /// `-VeselMeaning remSleep` opens the meaning sheet on the launch tab.
    var meaning: Term?
    var opensAboutYou: Bool
    var opensBandDataReport: Bool
    /// `-VeselForgetSheet confirm|lost` opens Forget this Loop at that step.
    var forgetSheet: ForgetStep?
    /// `-VeselPairingStep before|looking|aboutYou`.
    var pairingStep: PairingStep
    /// `-VeselDay 2026-10-20` opens Journal on that day; held to the first day with data … today.
    var day: DayKey?
    /// `-VeselPage recovery|sleep|stress|heartRate|steps|hrv|restingHeartRate|lowestHeartRate|breathing|skinTemperature` pushes that page on the launch tab (for Journal's day on Journal).
    var page: PageKind?
    /// `-VeselPeriod d|w|m|3m` opens `-VeselPage` in that view; D when absent.
    var period: PagePeriod
    /// `-VeselCalendar` opens Journal's calendar.
    var opensCalendar: Bool
    /// `-VeselFitness` opens Body with the heart fitness page pushed.
    var opensFitness: Bool
    /// `-VeselScrub 03:12` selects that clock time on the first scrubbable chart shown.
    var scrub: ScrubTime?
    /// `-VeselReadProblem` makes Today's first read fail once, to show the "Couldn't show this" card.
    var failsFirstRead: Bool

    init(defaults: UserDefaults) {
        tab = AppTab(defaults: defaults)
        #if targetEnvironment(simulator)
        let screen = defaults.string(forKey: "VeselScreen")
        opensLoopSettings = screen == "loop" || screen == "report" || screen == "syncing" || screen == "meanings"
        opensSyncing = screen == "syncing"
        opensMeanings = screen == "meanings"
        meaning = defaults.string(forKey: "VeselMeaning").flatMap(Term.init(rawValue:))
        opensAboutYou = screen == "aboutYou"
        if opensAboutYou { tab = .body }
        opensBandDataReport = screen == "report"
        forgetSheet = defaults.string(forKey: "VeselForgetSheet").flatMap { name in
            switch name {
            case "confirm": .confirm
            case "lost": .lost(lastRead: nil)
            default: nil
            }
        }
        pairingStep = defaults.string(forKey: "VeselPairingStep").flatMap(PairingStep.init(rawValue:)) ?? .before
        day = defaults.string(forKey: "VeselDay").flatMap(DayKey.init)
        page = defaults.string(forKey: "VeselPage").flatMap(PageKind.init(rawValue:))
        period = defaults.string(forKey: "VeselPeriod").flatMap(PagePeriod.init(launch:)) ?? .day
        opensCalendar = ProcessInfo.processInfo.arguments.contains("-VeselCalendar")
        opensFitness = ProcessInfo.processInfo.arguments.contains("-VeselFitness")
        if opensFitness { tab = .body }
        if opensCalendar { tab = .journal }
        scrub = defaults.string(forKey: "VeselScrub").flatMap(ScrubTime.init)
        failsFirstRead = ProcessInfo.processInfo.arguments.contains("-VeselReadProblem")
        #else
        opensLoopSettings = false
        opensSyncing = false
        opensMeanings = false
        meaning = nil
        opensAboutYou = false
        opensBandDataReport = false
        forgetSheet = nil
        pairingStep = .before
        day = nil
        page = nil
        period = .day
        opensCalendar = false
        opensFitness = false
        scrub = nil
        failsFirstRead = false
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
/// The system clock moved by a fixed amount, in one fixed zone.
struct ShiftedClock: VeselClock {
    let offset: TimeInterval
    let timeZone: TimeZone
    var now: Date { Date().addingTimeInterval(offset) }
}
#endif

extension LaunchOptions {
    /// The page the launch options push on the launch tab, for `day`.
    func routes(day: DayKey) -> [PageRoute] {
        page.map { [PageRoute(kind: $0, day: day, period: period)] } ?? []
    }
}

#if DEBUG
extension LaunchOptions {
    /// `-VeselStorageProblem olderApp|setUp|couldNotOpen` makes opening the database fail that way, to see the recovery screen.
    static func storageProblem(defaults: UserDefaults) -> StorageError? {
        switch defaults.string(forKey: "VeselStorageProblem") {
        case "olderApp"?: .newerSchema
        case "setUp"?: .noAppGroup
        case "couldNotOpen"?: .notOpened
        default: nil
        }
    }
}
#endif
