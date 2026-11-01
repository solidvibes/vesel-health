import Foundation
import Testing
@testable import VeselStorage

struct BackupExclusionTests {
    @Test func databaseFolderIsExcludedFromBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vesel-\(UUID().uuidString)/Vesel")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        let database = try AppDatabase.open(in: directory)
        try database.writer.writeWithoutTransaction { try $0.execute(sql: "PRAGMA user_version") }

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func walFilesStayAfterClosingSoReadOnlyReadersCanOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vesel-\(UUID().uuidString)/Vesel")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        do {
            let database = try AppDatabase.open(in: directory)
            try database.writer.writeWithoutTransaction { try $0.execute(sql: "PRAGMA user_version") }
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(Set(files).isSuperset(of: ["vesel.sqlite", "vesel.sqlite-wal", "vesel.sqlite-shm"]))
    }

    @Test func reopeningKeepsTheData() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vesel-\(UUID().uuidString)/Vesel")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        try await AppDatabase.open(in: directory).save(.init(birthYear: 1990, sex: .female, heightCm: 170, weightKg: 60, sleepGoalMinutes: 480))
        #expect(try await AppDatabase.open(in: directory).profile()?.sex == .female)
    }
}
