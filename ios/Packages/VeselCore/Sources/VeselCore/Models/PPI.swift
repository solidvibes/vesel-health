import Foundation

/// One beat-to-beat recording: the band records these in short sessions.
public struct PPISession: Sendable, Equatable {
    public var start: Date
    public var trigger: PPITrigger
    public var utcOffsetSeconds: Int
    public var samples: [PPISample]

    public init(start: Date, trigger: PPITrigger, utcOffsetSeconds: Int, samples: [PPISample]) {
        self.start = start
        self.trigger = trigger
        self.utcOffsetSeconds = utcOffsetSeconds
        self.samples = samples
    }
}

public struct PPISample: Sendable, Equatable {
    public var time: Date
    public var intervalMs: Int
    public var errorMs: Int
    public var blocker: Bool
    /// False only when the band reported no contact; a beat it reported nothing for counts as worn.
    public var skinContact: Bool

    public init(time: Date, intervalMs: Int, errorMs: Int, blocker: Bool, skinContact: Bool) {
        self.time = time
        self.intervalMs = intervalMs
        self.errorMs = errorMs
        self.blocker = blocker
        self.skinContact = skinContact
    }
}

public enum PPITrigger: String, Sendable, Codable {
    case automatic, manual, unknown
}
