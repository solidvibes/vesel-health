import Foundation
import VeselCore
import VeselStorage
import WidgetKit

struct VeselEntry: TimelineEntry {
    /// The moment the entry is for; every "is it old" decision uses this, never the clock.
    let date: Date
    let snapshot: WidgetSnapshot

    var content: WidgetSnapshot.Content { snapshot.content }
    var isStale: Bool { snapshot.isStale(at: date) }
    var stress: StressGlance { snapshot.stress(at: date) }

    /// "Updated 06:00", with the weekday when it was not today. Only for a stale snapshot.
    var updatedText: String? {
        guard isStale, let syncedAt = snapshot.syncedAt else { return nil }
        let sameDay = Calendar.current.isDate(syncedAt, inSameDayAs: date)
        let time = syncedAt.formatted(date: .omitted, time: .shortened)
        return sameDay ? "Updated \(time)" : "Updated \(syncedAt.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

/// One read of the shared database per timeline, then a refresh request an hour later (iOS decides the real time).
struct Provider: TimelineProvider {
    static let refreshAfter: TimeInterval = 3600
    static let retryAfter: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> VeselEntry {
        VeselEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (VeselEntry) -> Void) {
        #if DEBUG
        if context.isPreview { return completion(VeselEntry(date: .now, snapshot: .sampleReady(at: .now))) }
        #endif
        completion(VeselEntry(date: .now, snapshot: (try? Self.read(at: .now)) ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<VeselEntry>) -> Void) {
        let now = Date.now
        do {
            let entry = VeselEntry(date: now, snapshot: try Self.read(at: now))
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.refreshAfter))))
        } catch {
            completion(Timeline(entries: [VeselEntry(date: now, snapshot: .empty)], policy: .after(now.addingTimeInterval(Self.retryAfter))))
        }
    }

    private static func read(at date: Date) throws -> WidgetSnapshot {
        try AppDatabase.readSnapshot(today: DayKey(date, in: .current))
    }
}
