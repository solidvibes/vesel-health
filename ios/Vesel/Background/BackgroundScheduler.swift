import BackgroundTasks
import UIKit
import VeselCore

/// Background app refresh: iOS picks when it runs (often a few times a day), never sooner than asked.
/// The long read: a processing task iOS runs while the phone charges and is idle, usually at night; it gets minutes.
enum BackgroundScheduler {
    static let refreshIdentifier = "app.vesel.ios.refresh"
    static let longReadIdentifier = "app.vesel.ios.catchup"
    static let earliestGap: TimeInterval = 30 * 60
    static let longReadGap: TimeInterval = 60 * 60

    /// Must run before launch finishes, or iOS drops the task, so it runs even when the database couldn't be opened.
    /// Without an environment a task tries to open it again, and ends as failed if it still can't.
    @MainActor
    static func register(_ startup: AppStartup) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: .main) { bgTask in
            // Registered `using: .main`, so iOS calls this on the main queue; the compiler can't see that.
            MainActor.assumeIsolated {
                let task = OnceTask(bgTask)
                schedule()
                startup.retry()
                guard let environment = startup.environment else { return task.complete(success: false) }
                let run = Task { await environment.backgroundSync(.backgroundRefresh) }
                bgTask.expirationHandler = {
                    environment.pipeline.expire()
                    Task { @MainActor in task.complete(success: false) }
                }
                Task {
                    let outcome = await run.value
                    task.complete(success: outcome == .success)
                }
            }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: longReadIdentifier, using: .main) { bgTask in
            // Registered `using: .main`, so iOS calls this on the main queue; the compiler can't see that.
            MainActor.assumeIsolated {
                let task = OnceTask(bgTask)
                Task { await scheduleLongRead() }
                startup.retry()
                guard let environment = startup.environment else { return task.complete(success: false) }
                let run = Task { await environment.heldSync(.longRead) }
                bgTask.expirationHandler = {
                    run.cancel()
                    Task { @MainActor in
                        // iOS ends it when the phone is picked up: the database sleeps only if Vesel isn't on screen.
                        if UIApplication.shared.applicationState == .background { environment.pipeline.expire() }
                        task.complete(success: false)
                    }
                }
                Task {
                    let outcome = await run.value
                    task.complete(success: outcome == .success)
                }
            }
        }
    }

    /// Asks for the next refresh. Called at launch and at the start of every refresh.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestGap)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Asks for a long read while charging, unless one is already asked for. Called at launch and at the start of every long read.
    static func scheduleLongRead() async {
        let pending = await BGTaskScheduler.shared.pendingTaskRequests()
        guard !pending.contains(where: { $0.identifier == longReadIdentifier }) else { return }
        let request = BGProcessingTaskRequest(identifier: longReadIdentifier)
        request.requiresExternalPower = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: longReadGap)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// One background task run; tells iOS it finished exactly once.
@MainActor
final class OnceTask {
    private let task: BGTask
    private var completed = false

    init(_ task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        guard !completed else { return }
        completed = true
        task.setTaskCompleted(success: success)
    }
}
