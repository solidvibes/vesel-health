import Foundation
import Testing
import VeselBackupKit

struct ServerHomeTests {
    @Test func theStandardFolderIsTheTerminalSetUpsOne() {
        let home = ServerHome.standard(userHome: URL(filePath: "/Users/owner"))
        #expect(home.root.path == "/Users/owner/Library/Application Support/vesel-server")
        #expect(home.tokenHash.path == "/Users/owner/Library/Application Support/vesel-server/token.sha256")
        #expect(home.certificate.path == "/Users/owner/Library/Application Support/vesel-server/certs/cert.pem")
    }

    @Test func pairedOnlyWhenAllThreeFilesExist() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let home = ServerHome(root: folder)
        try FileManager.default.createDirectory(at: home.certs, withIntermediateDirectories: true)
        #expect(!home.isPaired)
        try Data().write(to: home.certificate)
        try Data().write(to: home.privateKey)
        #expect(!home.isPaired)
        try Data().write(to: home.tokenHash)
        #expect(home.isPaired)
        try FileManager.default.removeItem(at: home.privateKey)
        #expect(!home.isPaired)
    }

    @Test func theSweepSetsFoldersTo700AndFilesTo600() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let home = ServerHome(root: folder)
        try FileManager.default.createDirectory(at: home.certs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.venv, withIntermediateDirectories: true)
        let files = [home.certificate, home.privateKey, home.tokenHash, home.log, home.database, folder.appending(path: "vesel.sqlite-wal")]
        for file in files {
            try Data().write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        }
        for folder in [home.root, home.certs, home.venv] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }

        try home.sweepPermissions()

        for folder in [home.root, home.certs, home.venv] {
            #expect(try mode(folder) == 0o700)
        }
        for file in files {
            #expect(try mode(file) == 0o600)
        }
    }

    @Test func thePidFileRoundTrips() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let home = ServerHome(root: folder)
        #expect(home.readPid() == nil)
        try home.writePid(4242)
        #expect(home.readPid() == 4242)
        #expect(try mode(home.pidFile) == 0o600)
        home.removePid()
        #expect(home.readPid() == nil)
    }
}
