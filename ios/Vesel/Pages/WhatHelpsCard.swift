import SwiftUI
import VeselCore

/// "What tends to help": general tips for what was off, from `WhatHelps`. Nothing when there are none. When a tip names
/// your usual bedtime, its working-out sits at the foot.
struct WhatHelpsCard: View {
    let tips: [String]
    let usualBedtime: UsualBedtime?

    var body: some View {
        if !tips.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    Text("What tends to help")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                        ForEach(tips, id: \.self) { tip in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s8) {
                                Text("•").accessibilityHidden(true)
                                Text(tip).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.text)
                        }
                    }
                    Text(WhatHelps.label)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let bedtime = usualBedtime, tips.contains(where: { $0.contains("about \(bedtime.text)") }) {
                        Divider()
                        HowItsWorkedOutRow(
                            framed: false, title: "How your usual bedtime is worked out", explanations: [bedtime.explanation], labels: ["Your usual bedtime"])
                    }
                }
            }
        }
    }
}
