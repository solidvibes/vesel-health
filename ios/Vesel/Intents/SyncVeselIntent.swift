import AppIntents

/// "Sync Vesel" for Shortcuts, e.g. a personal automation "When my alarm is stopped". Runs in the background without
/// opening Vesel. If the band still records sleep it ends the night first: running it is deliberate.
struct SyncVeselIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Vesel"
    static let description = IntentDescription("Reads your Polar Loop. If it is still recording sleep, ends the night first so last night is ready now.")
    static let supportedModes: IntentModes = .background

    @Dependency private var startup: AppStartup

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        startup.retry()
        guard let environment = startup.environment else { return .result(dialog: "Open Vesel first.") }
        switch await environment.shortcutSync() {
        case .lastNight(let asleep, let recharge)?:
            return .result(dialog: "Last night: \(asleep), recharge \(recharge).")
        case .nightNotReady?:
            return .result(dialog: "Your Loop is read. Polar is still finishing last night; Vesel fills it in on the next sync.")
        case .notNearby?:
            return .result(dialog: "Your Loop isn't nearby.")
        case nil:
            return .result(dialog: "Pair your Loop in Vesel first.")
        }
    }
}
