import Foundation

/// After an unexpected exit the server restarts in 5 s; the third exit within 10 minutes stops trying.
public struct RestartPolicy: Sendable {
    public static let delay: Duration = .seconds(5)
    static let window: TimeInterval = 10 * 60
    static let limit = 3

    private var exits: [Date] = []

    public init() {}

    /// Records an exit and says whether to restart.
    public mutating func shouldRestart(afterExitAt time: Date) -> Bool {
        exits = exits.filter { time.timeIntervalSince($0) < Self.window } + [time]
        return exits.count < Self.limit
    }

    public mutating func reset() {
        exits = []
    }
}
