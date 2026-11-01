import Foundation
import GRDB
import VeselCore

/// An alert that went out, or is due at 07:00. One per kind per day.
struct AlertEventRecord: UpsertRecord {
    static let databaseTableName = "alert_event"
    static let keyColumns: Set<String> = ["kind", "day"]

    var kind: String
    var day: String
    var firedAt: Int64
    var title: String
    var body: String
    var explanationJson: String

    init(_ event: AlertEvent) throws {
        kind = event.kind.rawValue
        day = event.day.description
        firedAt = event.firedAt.unixSeconds
        title = event.title
        body = event.body
        explanationJson = try StoredJSON.encode(event.explanation)
    }

    func model() throws -> AlertEvent? {
        guard let kind = AlertKind(rawValue: kind), let day = DayKey(day) else { return nil }
        let alert = Alert(kind: kind, day: day, title: title, body: body, explanation: try StoredJSON.decode(Explanation.self, from: explanationJson))
        return AlertEvent(alert, firedAt: Date(unixSeconds: firedAt))
    }
}
