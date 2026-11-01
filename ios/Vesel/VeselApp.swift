import SwiftUI

@main
struct VeselApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            let startup = appDelegate.startup
            if let environment = startup.environment {
                RootView(environment: environment, router: environment.router)
                    .onOpenURL { environment.router.open($0) }
            } else if let problem = startup.problem {
                StorageProblemView(problem: problem) { sceneChanged(to: .active) }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            sceneChanged(to: phase)
        }
    }

    private func sceneChanged(to phase: ScenePhase) {
        if phase == .active { appDelegate.startup.retry() }
        guard let environment = appDelegate.startup.environment else { return }
        switch phase {
        case .active:
            environment.database.resume()
            environment.liveHeartRate.sceneBecameActive()
            Task { await environment.foreground() }
        case .inactive:
            environment.liveHeartRate.sceneLeftScreen()
        case .background:
            environment.liveHeartRate.sceneLeftScreen()
            environment.pipeline.suspendIfIdle()
        @unknown default: break
        }
    }
}
