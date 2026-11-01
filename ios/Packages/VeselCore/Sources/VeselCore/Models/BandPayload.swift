/// What the band can be asked for, one kind per fetch.
public enum FetchKind: String, Sendable, Codable, CaseIterable {
    case sleep, nightlyRecharge, heartRate, ppi, skinTemperature, activitySamples, dailySummary
}

/// One day of one kind, exactly as it came off the band. Each band-local wall time carries its UTC offset;
/// `utcOffsetSeconds` is the day's offset at noon, for times stored before they carried one.
public struct BandPayload: Sendable, Equatable {
    public var day: DayKey
    public var kind: FetchKind
    public var json: String
    public var utcOffsetSeconds: Int
    public var sampleCount: Int

    public init(day: DayKey, kind: FetchKind, json: String, utcOffsetSeconds: Int, sampleCount: Int) {
        self.day = day
        self.kind = kind
        self.json = json
        self.utcOffsetSeconds = utcOffsetSeconds
        self.sampleCount = sampleCount
    }
}

extension BandPayload {
    /// A fetched day with nothing in it: the band wasn't worn, or the data was already cleared.
    public static func empty(day: DayKey, kind: FetchKind, utcOffsetSeconds: Int) -> BandPayload {
        BandPayload(day: day, kind: kind, json: "{}", utcOffsetSeconds: utcOffsetSeconds, sampleCount: 0)
    }

    public var isEmpty: Bool { sampleCount == 0 }
}
