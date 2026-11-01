import Foundation
import VeselStorage

/// Upload format v1, shared with `server/`: `{schema, table, rows: [{key, data}]}`.
enum UploadFormat {
    static let schema = 1
    /// The server takes up to 1000 rows and 5 MB per batch; stay under both.
    static let rowsPerBatch = 500
    static let bytesPerBatch = 4 * 1024 * 1024

    struct Batch: Encodable {
        let schema = UploadFormat.schema
        let table: String
        let rows: [Row]
    }

    struct Row: Encodable {
        let key: String
        let data: [String: UploadValue]

        init(_ pending: PendingUpload) {
            key = pending.key
            data = pending.data
        }
    }

    struct Status: Decodable {
        let schema: Int
    }

    /// Non-finite numbers throw (the default), so they never reach the server.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
}
