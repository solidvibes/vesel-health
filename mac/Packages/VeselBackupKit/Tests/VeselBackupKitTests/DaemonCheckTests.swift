import Foundation
import Testing
import VeselBackupKit

struct DaemonCheckTests {
    @Test func installedOnlyWhenThePlistExists() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plist = folder.appending(path: "app.vesel.server.plist")
        #expect(!DaemonCheck.isInstalled(plist: plist))
        try Data().write(to: plist)
        #expect(DaemonCheck.isInstalled(plist: plist))
        #expect(DaemonCheck.standardPlist.path == "/Library/LaunchDaemons/app.vesel.server.plist")
    }
}
