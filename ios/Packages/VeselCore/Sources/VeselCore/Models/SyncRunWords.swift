import Foundation

/// The sync log in plain words. `detail` is only mapped, never shown as it is.
public enum SyncRunWords {
    public static func trigger(_ trigger: SyncTrigger) -> String {
        switch trigger {
        case .launch, .foreground: "you opened Vesel"
        case .bandEvent: "your Loop asked"
        case .bandCheckIn: "your Loop checked in"
        case .longRead: "long read while charging"
        case .backgroundRefresh: "iOS woke Vesel"
        case .shortcut: "Shortcut"
        case .manual: "Sync now"
        case .imUp: "I'm up"
        case .paired: "after pairing"
        }
    }

    /// `isRunning` is true only for the newest run while the app is reading the band; any other run without an outcome was cut off.
    public static func outcome(_ run: SyncRun, isRunning: Bool = false) -> String {
        switch run.outcome {
        case .success?: "done"
        case .partial?: "partly done"
        case .unreachable?: run.detail == SyncDetail.didNotStart ? "Loop didn't answer" : "Loop not nearby"
        case .failed?:
            switch run.detail {
            case SyncDetail.stoppedEarly: "stopped early"
            case SyncDetail.notPaired: "no Loop paired"
            default: "didn't finish"
            }
        case nil: isRunning ? "reading now…" : "didn't finish"
        }
    }
}
