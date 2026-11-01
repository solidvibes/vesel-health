import Foundation

public struct BandInfo: Sendable, Equatable {
    public var deviceId: String
    public var name: String
    public var pairedAt: Date
    public var firmware: String?
    public var batteryPercent: Int?
    public var batteryAt: Date?
    public var diskFreeBytes: Int64?
    public var diskTotalBytes: Int64?
    public var lastSeenAt: Date?

    public init(
        deviceId: String,
        name: String,
        pairedAt: Date,
        firmware: String? = nil,
        batteryPercent: Int? = nil,
        batteryAt: Date? = nil,
        diskFreeBytes: Int64? = nil,
        diskTotalBytes: Int64? = nil,
        lastSeenAt: Date? = nil
    ) {
        self.deviceId = deviceId
        self.name = name
        self.pairedAt = pairedAt
        self.firmware = firmware
        self.batteryPercent = batteryPercent
        self.batteryAt = batteryAt
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.lastSeenAt = lastSeenAt
    }

    /// Below 20 % at the last read; unknown counts as not low.
    public var isBatteryLow: Bool { batteryPercent.map { $0 < 20 } ?? false }
}
