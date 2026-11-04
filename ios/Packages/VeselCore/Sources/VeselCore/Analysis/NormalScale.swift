/// Where a value and its normal sit on a track one normal-width either side of the normal.
public enum NormalScale {
    /// `floor` and `ceiling` stop the track at 0 for a duration or at 100 for a percentage; a value past either end sits at that end.
    public static func scale(value: Double, low: Double, high: Double, floor: Double? = nil, ceiling: Double? = nil) -> LineScale {
        var width = high - low
        if width <= 0 { width = max(abs(low) * 0.1, 1) }
        let trackLow = max(low - width, floor ?? -.infinity)
        let trackHigh = min(high + width, ceiling ?? .infinity)
        return LineScale(trackLow: trackLow, trackHigh: trackHigh, normalLow: low, normalHigh: high, value: value)
    }
}
