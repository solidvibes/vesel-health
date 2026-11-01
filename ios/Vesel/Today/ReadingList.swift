import SwiftUI
import VeselCore

/// The parts of a read as they arrive: a tick for each part that is in, the one being read marked, the rest waiting.
/// Counts only, never health values.
struct ReadingList: View {
    let progress: SyncProgress
    /// The "Last night" row; left out once last night is on the phone (the Loop is still asked).
    var showsNight = true

    private enum Mark { case done, active, waiting }

    private struct Row: Identifiable {
        let id: Int
        let title: String
        let spoken: String
        let mark: Mark
        /// The heart-rate row while it is being read: the green pulsing dot.
        let live: Bool
    }

    private var rows: [Row] {
        var parts: [(title: String, spoken: String, done: Bool, isHeartRate: Bool)] = [
            ("Loop found", "Loop found", progress.loopFound, false),
            ("Heart rate", "heart rate", progress.heartRate, true),
        ]
        if showsNight, progress.nightPartsTotal > 0 {
            let counted = "\(progress.nightParts) of \(progress.nightPartsTotal) parts"
            parts.append(("Last night · \(counted)", "last night \(counted)", progress.nightParts >= progress.nightPartsTotal, false))
        }
        parts.append(("Stress today", "stress today", progress.stressToday, false))
        let firstOpen = parts.firstIndex { !$0.done }
        return parts.enumerated().map { index, part in
            let mark: Mark = part.done ? .done : (index == firstOpen ? .active : .waiting)
            let live = part.isHeartRate && mark == .active
            let spoken = part.done && part.spoken != "Loop found" && !part.spoken.contains(" of ") ? part.spoken + " done" : part.spoken
            return Row(id: index, title: live ? "\(part.title) · reading" : part.title, spoken: spoken, mark: mark, live: live)
        }
    }

    var body: some View {
        let rows = rows
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                ForEach(rows) { row in
                    HStack(spacing: Theme.Spacing.s12) {
                        icon(row)
                            .frame(width: 20, height: 20)
                        Text(row.title)
                            .font(Theme.Typography.body)
                            .foregroundStyle(row.mark == .waiting ? Theme.Palette.mutedText : Theme.Palette.text)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading your Loop: " + rows.map(\.spoken).joined(separator: ", "))
    }

    @ViewBuilder private func icon(_ row: Row) -> some View {
        switch row.mark {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
        case .active:
            if row.live { LiveDot() } else { ProgressView().controlSize(.small) }
        case .waiting:
            Image(systemName: "circle").foregroundStyle(Theme.Palette.mutedText)
        }
    }
}
