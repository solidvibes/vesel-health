import Foundation
import GRDB
import Synchronization

/// A row written with "insert, or update only if a value changed". A changed row gets
/// `uploaded_at = NULL` so the Mac mini backup picks it up again; an unchanged row is left alone.
protocol UpsertRecord: Codable, FetchableRecord, PersistableRecord {
    static var conflictTarget: String { get }
    static var keyColumns: Set<String> { get }
    /// Columns that are refreshed with a change but don't count as one (such as `fetched_at`).
    static var bookkeepingColumns: Set<String> { get }
    static var tracksUpload: Bool { get }
}

extension UpsertRecord {
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var conflictTarget: String { keyColumns.sorted().joined(separator: ", ") }
    static var bookkeepingColumns: Set<String> { [] }
    static var tracksUpload: Bool { true }

    func upsert(_ db: Database) throws {
        let values = try databaseDictionary
        let columns = values.keys.sorted()
        try db.cachedStatement(sql: Self.upsertSQL(columns)).execute(arguments: StatementArguments(columns.map { values[$0]! }))
    }

    private static func upsertSQL(_ columns: [String]) -> String {
        let key = "\(Self.self) \(columns.joined(separator: ","))"
        return upsertStatements.withLock { cache in
            if let sql = cache[key] { return sql }
            let table = databaseTableName.quotedDatabaseIdentifier
            let updated = columns.filter { !keyColumns.contains($0) }
            let compared = updated.filter { !bookkeepingColumns.contains($0) }

            var assignments = updated.map { "\($0.quotedDatabaseIdentifier) = excluded.\($0.quotedDatabaseIdentifier)" }
            if tracksUpload {
                assignments.append("uploaded_at = NULL")
            }
            let changed =
                compared
                .map { "\(table).\($0.quotedDatabaseIdentifier) IS NOT excluded.\($0.quotedDatabaseIdentifier)" }
                .joined(separator: " OR ")
            let sql = """
                INSERT INTO \(table) (\(columns.map(\.quotedDatabaseIdentifier).joined(separator: ", ")))
                VALUES (\(databaseQuestionMarks(count: columns.count)))
                ON CONFLICT (\(conflictTarget)) DO UPDATE SET \(assignments.joined(separator: ", "))
                WHERE \(changed)
                """
            cache[key] = sql
            return sql
        }
    }
}

/// Upsert SQL per record type and column set, built once.
private let upsertStatements = Mutex<[String: String]>([:])

extension Date {
    var unixSeconds: Int64 { Int64(timeIntervalSince1970.rounded(.down)) }
    var unixMilliseconds: Int64 { Int64((timeIntervalSince1970 * 1000).rounded(.down)) }

    init(unixSeconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(unixSeconds))
    }

    init(unixMilliseconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(unixMilliseconds) / 1000)
    }
}

enum StoredJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(string.utf8))
    }
}
