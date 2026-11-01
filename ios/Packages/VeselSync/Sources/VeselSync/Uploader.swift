import Foundation
import VeselCore
import VeselStorage

/// Sends every row not yet backed up to the Mac mini, table by table, and marks uploaded exactly the rows it
/// acknowledged. Away from home the first call gets no answer within 5 seconds and nothing changes; the rows wait.
public struct Uploader: Sendable {
    /// No answer this fast means the Mac mini isn't on this network. Leaves room for an IPv6 try to fall back to IPv4.
    static let reachTimeout: TimeInterval = 5
    static let batchTimeout: TimeInterval = 30

    private let config: BackupConfig
    private let token: String
    private let database: AppDatabase
    private let transport: any BackupTransport
    private let clock: any VeselClock

    public init(config: BackupConfig, token: String, database: AppDatabase, transport: any BackupTransport, clock: any VeselClock) {
        self.config = config
        self.token = token
        self.database = database
        self.transport = transport
        self.clock = clock
    }

    /// Asks the Mac mini whether it is there and speaks format v1. Set-up uses this as its test call.
    public func check() async -> BackupOutcome? {
        do {
            let (data, response) = try await transport.send(request("v1/status", timeout: Self.reachTimeout))
            if let failure = Self.outcome(response.statusCode) { return failure }
            guard (try? JSONDecoder().decode(UploadFormat.Status.self, from: data))?.schema == UploadFormat.schema else { return .otherFormat }
            return nil
        } catch {
            return Self.outcome(error)
        }
    }

    /// Runs one backup and records how it went. Stops between batches when the task is cancelled.
    @discardableResult
    public func run() async -> BackupOutcome {
        let outcome = await upload()
        if !Task.isCancelled {
            try? await BackupRecord.save(outcome, at: clock.now, to: database)
        }
        return outcome
    }

    private func upload() async -> BackupOutcome {
        if let failure = await check() { return failure }
        for table in UploadTable.allCases {
            var after: Int64 = 0
            while !Task.isCancelled {
                guard let page = try? await database.pendingUploads(table, after: after, limit: UploadFormat.rowsPerBatch, now: clock.now)
                else { return .failed }
                guard let last = page.last else { break }
                after = last.rowID
                for batch in Self.batches(page) {
                    if let failure = await send(batch, table: table) { return failure }
                }
            }
        }
        return Task.isCancelled ? .failed : .backedUp
    }

    private func send(_ rows: [PendingUpload], table: UploadTable) async -> BackupOutcome? {
        do {
            var request = request("v1/batches", timeout: Self.batchTimeout)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try UploadFormat.encode(UploadFormat.Batch(table: table.rawValue, rows: rows.map(UploadFormat.Row.init)))
            let (_, response) = try await transport.send(request)
            if let failure = Self.outcome(response.statusCode) { return failure }
            try await database.markUploaded(table, rows, at: clock.now)
            return nil
        } catch {
            return Self.outcome(error)
        }
    }

    /// Splits a page so each batch stays under the size limit. A row too big to ever fit stays queued.
    static func batches(_ page: [PendingUpload]) -> [[PendingUpload]] {
        var batches: [[PendingUpload]] = []
        var current: [PendingUpload] = []
        var bytes = 0
        for row in page {
            guard let size = try? UploadFormat.encode(UploadFormat.Row(row)).count, size < UploadFormat.bytesPerBatch else { continue }
            if bytes + size > UploadFormat.bytesPerBatch, !current.isEmpty {
                batches.append(current)
                current = []
                bytes = 0
            }
            current.append(row)
            bytes += size + 1
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    private func request(_ path: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: config.baseURL.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func outcome(_ status: Int) -> BackupOutcome? {
        switch status {
        case 200: nil
        case 401: .unauthorized
        case 409: .otherFormat
        default: .failed
        }
    }

    private static func outcome(_ error: any Error) -> BackupOutcome {
        if case BackupTransportError.wrongCertificate = error { return .wrongCertificate }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
                .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                return .away
            default:
                return .failed
            }
        }
        return .failed
    }
}
