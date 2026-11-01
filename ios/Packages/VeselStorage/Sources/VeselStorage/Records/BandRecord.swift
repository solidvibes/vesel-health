import Foundation
import GRDB
import VeselCore

struct BandRecord: UpsertRecord {
    static let databaseTableName = "band"
    static let keyColumns: Set<String> = ["id"]
    static let tracksUpload = false

    var id = 1
    var deviceId: String
    var name: String
    var pairedAt: Int64
    var firmware: String?
    var battery: Int?
    var batteryAt: Int64?
    var diskFree: Int64?
    var diskTotal: Int64?
    var lastSeenAt: Int64?

    init(_ band: BandInfo) {
        deviceId = band.deviceId
        name = band.name
        pairedAt = band.pairedAt.unixSeconds
        firmware = band.firmware
        battery = band.batteryPercent
        batteryAt = band.batteryAt?.unixSeconds
        diskFree = band.diskFreeBytes
        diskTotal = band.diskTotalBytes
        lastSeenAt = band.lastSeenAt?.unixSeconds
    }

    var model: BandInfo {
        BandInfo(
            deviceId: deviceId,
            name: name,
            pairedAt: Date(unixSeconds: pairedAt),
            firmware: firmware,
            batteryPercent: battery,
            batteryAt: batteryAt.map(Date.init(unixSeconds:)),
            diskFreeBytes: diskFree,
            diskTotalBytes: diskTotal,
            lastSeenAt: lastSeenAt.map(Date.init(unixSeconds:))
        )
    }
}
