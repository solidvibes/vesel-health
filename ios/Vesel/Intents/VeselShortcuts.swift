import AppIntents

struct VeselShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncVeselIntent(),
            phrases: ["Sync \(.applicationName)"],
            shortTitle: "Sync Vesel",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
