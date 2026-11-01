import GRDB

/// One of the owner's switches. Not health data, so not backed up.
struct SettingRecord: UpsertRecord {
    static let databaseTableName = "setting"
    static let keyColumns: Set<String> = ["key"]
    static let tracksUpload = false

    var key: String
    var value: String
}
