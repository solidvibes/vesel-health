import Foundation
import GRDB
import VeselCore

struct RawExportRecord: UpsertRecord {
    static let databaseTableName = "raw_export"
    static let keyColumns: Set<String> = ["day", "kind"]
    static let bookkeepingColumns: Set<String> = ["fetched_at"]

    var day: String
    var kind: String
    var json: String
    var utcOffsetSeconds: Int
    var fetchedAt: Int64

    init(_ payload: BandPayload, fetchedAt: Date) {
        day = payload.day.description
        kind = payload.kind.rawValue
        json = payload.json
        utcOffsetSeconds = payload.utcOffsetSeconds
        self.fetchedAt = fetchedAt.unixSeconds
    }
}

/// What was fetched from the band, and when it was cleared off it. A fetched day gets a row even when it was empty.
struct BandLedgerRecord: Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "band_ledger"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var day: String
    var fetchKind: String
    var storedAt: Int64
    var sampleCount: Int
    var deletedFromBandAt: Int64?
    var earlierEmptyAt: Int64?

    var model: LedgerEntry? {
        guard let day = DayKey(day), let kind = FetchKind(rawValue: fetchKind) else { return nil }
        return LedgerEntry(
            day: day,
            kind: kind,
            storedAt: Date(unixSeconds: storedAt),
            sampleCount: sampleCount,
            deletedFromBandAt: deletedFromBandAt.map(Date.init(unixSeconds:)),
            earlierEmptyAt: earlierEmptyAt.map(Date.init(unixSeconds:))
        )
    }
}

struct SyncRunRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "sync_run"
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: Int64?
    var trigger: String
    var startedAt: Int64
    var finishedAt: Int64?
    var outcome: String?
    var detail: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var model: SyncRun {
        SyncRun(
            id: id!,
            trigger: SyncTrigger(rawValue: trigger) ?? .manual,
            startedAt: Date(unixSeconds: startedAt),
            finishedAt: finishedAt.map(Date.init(unixSeconds:)),
            outcome: outcome.flatMap(SyncOutcome.init(rawValue:)),
            detail: detail
        )
    }
}

struct ComputedMetricRecord: UpsertRecord {
    static let databaseTableName = "computed_metric"
    static let keyColumns: Set<String> = ["kind", "day", "hour"]
    static let conflictTarget = "kind, day, ifnull(hour, -1)"
    static let bookkeepingColumns: Set<String> = ["computed_at"]

    var kind: String
    var day: String
    var hour: Int?
    var value: Double
    var unit: String
    var method: String
    var methodVersion: Int
    var inputsJson: String
    var computedAt: Int64

    /// `inputs_json` holds the explanation's inputs and its sentence; method and version have their own columns.
    private struct StoredExplanation: Codable {
        var inputs: [Explanation.Input]
        var text: String
    }

    init(_ metric: ComputedMetric) throws {
        kind = metric.kind
        day = metric.day.description
        hour = metric.hour
        value = metric.value
        unit = metric.unit
        method = metric.explanation.method
        methodVersion = metric.explanation.version
        inputsJson = try StoredJSON.encode(StoredExplanation(inputs: metric.explanation.inputs, text: metric.explanation.text))
        computedAt = metric.computedAt.unixSeconds
    }

    func model() throws -> ComputedMetric {
        let stored = try StoredJSON.decode(StoredExplanation.self, from: inputsJson)
        return ComputedMetric(
            kind: kind,
            day: try DayKey(stored: day),
            hour: hour,
            value: value,
            unit: unit,
            explanation: Explanation(method: method, version: methodVersion, inputs: stored.inputs, text: stored.text),
            computedAt: Date(unixSeconds: computedAt)
        )
    }
}
