import Charts
import SwiftUI
import VeselCore

/// The first nights, before there is a usual range: the median so far (from night 2) and how many earlier nights it rests on.
struct Settling: Equatable {
    var median: Double?
    var earlierNights: Int

    var caption: String { LearningText.nights(earlierNights) }
}

/// A faint dashed line across the chart at the median of the nights so far.
struct SettlingRule: ChartContent {
    let median: Double
    let color: Color

    var body: some ChartContent {
        RuleMark(y: .value("Median so far", median))
            .foregroundStyle(color.opacity(0.4))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}
