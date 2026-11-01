import Foundation
import Testing
import VeselBackupKit

struct PairingCodeTests {
    static let token = String(repeating: "a", count: 42) + "_"
    static let pin = "a3l7wTRF0MptFiOl69i0seA8pdtAfHQ37RiKObVEjVc%3D"

    @Test func acceptsWhatSetupShPrints() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let launch = ServerLaunch(
            userHome: URL(filePath: NSHomeDirectory()),
            temporaryDirectory: folder,
            serverHome: ServerHome(root: folder.appending(path: "home")),
            bundledServer: Repo.server,
            hostOverride: "localhost"
        )
        let command = launch.setup()
        let process = Process()
        let output = Pipe()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let code = try #require(PairingCode.parse(String(decoding: data, as: UTF8.self)))
        #expect(code.host == "localhost")
        #expect(!code.description.contains("token"))
    }

    @Test func acceptsAWellFormedLine() {
        #expect(PairingCode.parse("vesel-backup://mac.local:8443?token=\(Self.token)&pin=\(Self.pin)\n")?.host == "mac.local")
    }

    @Test(arguments: [
        "https://mac.local:8443?token=\(PairingCodeTests.token)&pin=\(PairingCodeTests.pin)",
        "vesel-backup://mac.local:443?token=\(PairingCodeTests.token)&pin=\(PairingCodeTests.pin)",
        "vesel-backup://mac.local?token=\(PairingCodeTests.token)&pin=\(PairingCodeTests.pin)",
        "vesel-backup://mac.local:8443?token=\(PairingCodeTests.token.dropLast())&pin=\(PairingCodeTests.pin)",
        "vesel-backup://mac.local:8443?token=\(PairingCodeTests.token.dropLast())%2B&pin=\(PairingCodeTests.pin)",
        "vesel-backup://mac.local:8443?token=\(PairingCodeTests.token)",
        "vesel-backup://mac.local:8443?token=\(PairingCodeTests.token)&pin=",
        "openssl is missing.",
        "",
    ])
    func rejectsAnythingElse(line: String) {
        #expect(PairingCode.parse(line) == nil)
    }
}
