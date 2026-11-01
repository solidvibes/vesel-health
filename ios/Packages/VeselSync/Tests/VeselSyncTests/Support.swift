import Foundation
import Synchronization
import VeselSync

/// Answers the uploader like the Mac mini would, and keeps every request it got.
final class FakeMacMini: BackupTransport {
    struct Sent {
        var path: String
        var authorization: String?
        var table: String?
        var keys: [String]
        var rows: [[String: Any]]
    }

    typealias Handler = @Sendable (Sent) async throws -> Int
    private let handler: Handler
    private let log = Mutex<[Sent]>([])

    init(_ handler: @escaping Handler = { _ in 200 }) {
        self.handler = handler
    }

    var sent: [Sent] { log.withLock { $0 } }
    var batches: [Sent] { sent.filter { $0.path == "/v1/batches" } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var sent = Sent(path: request.url!.path, authorization: request.value(forHTTPHeaderField: "Authorization"), table: nil, keys: [], rows: [])
        if let body = request.httpBody, let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            sent.table = json["table"] as? String
            let rows = json["rows"] as? [[String: Any]] ?? []
            sent.keys = rows.compactMap { $0["key"] as? String }
            sent.rows = rows.compactMap { $0["data"] as? [String: Any] }
        }
        log.withLock { $0.append(sent) }
        let status = try await handler(sent)
        let body = sent.path == "/v1/status" ? #"{"schema":1,"rows":0,"last_received_at":null}"# : #"{"stored":\#(sent.keys.count)}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

extension FakeMacMini.Sent: @unchecked Sendable {}

func at(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}
