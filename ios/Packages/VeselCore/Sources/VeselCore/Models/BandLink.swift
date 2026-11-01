import Foundation

/// One change in the Bluetooth link to the Loop, kept for 14 days to find out why it is away. Times and words only.
public struct BandLink: Sendable, Equatable {
    public static let keptFor: TimeInterval = 14 * 24 * 3600

    public enum Event: String, Sendable {
        case connecting, connected, disconnected, bluetoothOff, bluetoothOn
    }

    public var at: Date
    public var event: Event
    /// Why it disconnected, as the Polar SDK names it.
    public var reason: String?

    public init(at: Date, event: Event, reason: String? = nil) {
        self.at = at
        self.event = event
        self.reason = reason
    }
}
