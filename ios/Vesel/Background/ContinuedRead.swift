import BackgroundTasks
import UIKit
import VeselCore
import VeselStorage

/// Sync now and I'm up: the read keeps going after you leave Vesel. It first waits for the Loop on the app's own
/// background time, without iOS's card. Once the Loop answers it asks iOS for continued-processing time, whose card
/// "Reading your Loop" shows progress and a cancel; if iOS doesn't start it, the read carries on as it is. Every ending
/// completes that task. A cancel or expiry is like any cut-off read: nothing is cleared.
@MainActor
final class ContinuedRead {
    private let pipeline: SyncPipeline
    private let database: AppDatabase

    init(pipeline: SyncPipeline, database: AppDatabase) {
        self.pipeline = pipeline
        self.database = database
    }

    /// A card from an earlier launch never stays: a request iOS hasn't started yet is withdrawn.
    static func clearStale() async {
        for request in await BGTaskScheduler.shared.pendingTaskRequests() where request.identifier.contains(ReadCard.marker) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: request.identifier)
        }
    }

    @discardableResult
    func sync(_ trigger: SyncTrigger) async -> SyncOutcome? {
        let pipeline = pipeline
        let card = ReadCard()
        let reading = Task {
            await pipeline.runHeld(trigger) { step in
                await card.report(step)
            }
        }
        let time = BackgroundTime.begin("Sync Vesel", database: database) {
            reading.cancel()
            pipeline.expire()
        }
        // iOS's continued-processing time takes over from here.
        card.onStart = { time.end() }
        card.onExpire = {
            reading.cancel()
            if UIApplication.shared.applicationState == .background { pipeline.expire() }
        }
        let outcome = await reading.value
        card.finish(success: outcome == .success)
        time.end()
        return outcome
    }
}

/// iOS's "Reading your Loop" card for one read: asked for once the Loop answers, completed exactly once.
@MainActor
private final class ReadCard {
    static let marker = ".read."

    var onStart: () -> Void = {}
    var onExpire: () -> Void = {}
    private var identifier: String?
    private var task: OnceTask?
    private var progress: Progress?
    private var total: Int64 = 1
    private var done: Int64 = 0
    private var finished = false

    func report(_ step: SyncStep) {
        switch step {
        case .waitingForLoop: return
        case .loopFound:
            done = 1
            submit()
        case .kinds(let kinds): total = Int64(1 + kinds.count)
        case .fetched: done += 1
        }
        progress?.totalUnitCount = total
        progress?.completedUnitCount = done
    }

    func finish(success: Bool) {
        finished = true
        if let task {
            task.complete(success: success)
        } else if let identifier {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
    }

    /// Only while Vesel is on screen: iOS doesn't start this card from the background. Otherwise the read carries on in
    /// Vesel's own background time, and a cut-off read clears nothing.
    private func submit() {
        guard identifier == nil, !finished, UIApplication.shared.applicationState == .active,
            let bundle = Bundle.main.bundleIdentifier
        else { return }
        let identifier = "\(bundle)\(Self.marker)\(UUID().uuidString)"
        self.identifier = identifier
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            // Registered `using: .main`, so iOS calls this on the main queue; the compiler can't see that.
            MainActor.assumeIsolated {
                guard let self, !self.finished else {
                    task.setTaskCompleted(success: true)
                    return
                }
                self.began(task)
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Reading your Loop", subtitle: "Keeps going if you leave Vesel")
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            self.identifier = nil
        }
    }

    private func began(_ task: BGTask) {
        let once = OnceTask(task)
        self.task = once
        progress = (task as? BGContinuedProcessingTask)?.progress
        progress?.totalUnitCount = total
        progress?.completedUnitCount = done
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.onExpire()
                once.complete(success: false)
            }
        }
        onStart()
    }
}
