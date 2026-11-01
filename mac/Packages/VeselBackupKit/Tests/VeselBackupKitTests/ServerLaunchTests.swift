import Foundation
import Testing
import VeselBackupKit

struct ServerLaunchTests {
    let launch = ServerLaunch(
        userHome: URL(filePath: "/Users/owner"),
        temporaryDirectory: URL(filePath: "/var/folders/xy/abc/T/"),
        serverHome: ServerHome(root: URL(filePath: "/Users/owner/Library/Application Support/vesel-server")),
        bundledServer: URL(filePath: "/Applications/Vesel Backup.app/Contents/Resources/server"),
        hostOverride: nil
    )
    let base: Set<String> = ["HOME", "PATH", "TMPDIR", "VESEL_SERVER_HOME"]

    @Test func uvicornArgumentsMatchTheLaunchDaemon() throws {
        let plist = Repo.server.appending(path: "launchd/app.vesel.server.plist")
        let data = try Data(contentsOf: plist)
        let parsed = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let arguments = try #require(parsed["ProgramArguments"] as? [String])
        let afterUvicorn = try #require(arguments.firstIndex(of: "uvicorn")).advanced(by: 1)
        let daemon = arguments[afterUvicorn...].map {
            $0.replacingOccurrences(of: "__DATA__", with: "/Users/owner/Library/Application Support/vesel-server")
        }
        #expect(launch.uvicornArguments == Array(daemon))
    }

    @Test func theServerIsPythonRunningUvicornFromTheBundle() {
        let server = launch.server()
        #expect(server.executable.path == "/Users/owner/Library/Application Support/vesel-server/venv/bin/python")
        #expect(
            server.arguments == ["-m", "uvicorn"] + launch.uvicornArguments
                + ["--app-dir", "/Applications/Vesel Backup.app/Contents/Resources/server"])
        #expect(Set(server.environment.keys) == base.union(["PYTHONDONTWRITEBYTECODE"]))
        #expect(server.environment["PYTHONDONTWRITEBYTECODE"] == "1")
    }

    @Test func everyEnvironmentIsBuiltFromScratch() {
        let uv = URL(filePath: "/opt/homebrew/bin/uv")
        let sync = launch.sync(uv: uv)
        #expect(Set(sync.environment.keys) == base.union(["UV_PROJECT_ENVIRONMENT"]))
        #expect(sync.environment["UV_PROJECT_ENVIRONMENT"] == "/Users/owner/Library/Application Support/vesel-server/venv")
        #expect(sync.environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(sync.environment["HOME"] == "/Users/owner")
        #expect(sync.environment["TMPDIR"] == "/var/folders/xy/abc/T")
        #expect(sync.environment["VESEL_SERVER_HOME"] == "/Users/owner/Library/Application Support/vesel-server")
        #expect(sync.arguments == ["sync", "--frozen", "--no-dev", "--project", "/Applications/Vesel Backup.app/Contents/Resources/server"])

        let setup = launch.setup()
        #expect(Set(setup.environment.keys) == base)
        #expect(setup.executable.path == "/bin/bash")
        #expect(setup.arguments == ["/Applications/Vesel Backup.app/Contents/Resources/server/setup.sh", "--qr-text"])
    }

    @Test func aHostOverrideReachesSetupOnly() {
        let test = ServerLaunch(
            userHome: launch.userHome, temporaryDirectory: launch.temporaryDirectory, serverHome: launch.serverHome, bundledServer: launch.bundledServer,
            hostOverride: "localhost")
        #expect(test.setup().environment["VESEL_SERVER_HOST"] == "localhost")
        #expect(test.server().environment["VESEL_SERVER_HOST"] == nil)
    }
}
