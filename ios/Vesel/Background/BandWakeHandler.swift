import Foundation
import VeselCore
import VeselWearable

/// Syncs when the band reconnects, finishes a night, asks for it or checks in. iOS wakes, or relaunches, Vesel in the
/// background for these, as long as Vesel wasn't force-quit. One event at a time, so a reconnect's set-up runs before
/// any read it triggers; check-ins that arrive during a read end at once on the 5-minute gap (`SyncGap`). Only the
/// stand-up reminder runs beside the queue, so a read never holds it back.
@MainActor
final class BandWakeHandler {
    private var listening: Task<Void, Never>?
    private var handling: Task<Void, Never>?
    private var logging: Task<Void, Never>?

    func start(_ environment: AppEnvironment) {
        guard listening == nil else { return }
        let events = environment.bandSync.events
        let (queue, queued) = AsyncStream.makeStream(of: BandEvent.self)
        listening = Task {
            for await event in events {
                if case .stillTooLong(let alertedAt) = event {
                    Task { await environment.standUpReminder(alertedAt: alertedAt) }
                }
                queued.yield(event)
            }
        }
        handling = Task {
            for await event in queue {
                await handle(event, environment)
            }
        }
        // Each change in the link to the Loop goes into the connection log, in its own background time.
        logging = Task {
            for await link in environment.bandSync.links {
                let time = BackgroundTime.begin("Connection log", database: environment.database) {}
                try? await environment.database.save(link)
                time.end()
            }
        }
    }

    private func handle(_ event: BandEvent, _ environment: AppEnvironment) async {
        guard environment.isPaired == true else { return }
        switch event {
        case .connected:
            await environment.bandSync.bandConnected()
            await environment.pipeline.run(.bandEvent, onlyIfDue: true)
        case .sleepEnded, .syncRequested:
            // A read already running (a long read, Sync now) may have started before this; read afresh after it.
            await environment.pipeline.idle()
            await environment.pipeline.run(.bandEvent)
        case .checkIn, .stillTooLong, .workoutStarted, .workoutEnded:
            await environment.pipeline.run(.bandCheckIn, onlyIfDue: true)
        }
    }
}
