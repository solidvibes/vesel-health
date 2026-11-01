import Foundation

public struct Command: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
}

/// Builds the three processes the app runs. Every environment starts from scratch; nothing is inherited.
public struct ServerLaunch: Sendable {
    public static let port: UInt16 = 8443
    public static let systemPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    public let userHome: URL
    /// The per-user temporary folder (700), so `setup.sh`'s new key never sits in the shared `/tmp`.
    public let temporaryDirectory: URL
    public let serverHome: ServerHome
    /// The server code and `setup.sh` bundled in `Contents/Resources/server`.
    public let bundledServer: URL
    /// Debug test runs only: the name `setup.sh` puts in the certificate and QR (e.g. `localhost`).
    public let hostOverride: String?

    public init(userHome: URL, temporaryDirectory: URL, serverHome: ServerHome, bundledServer: URL, hostOverride: String?) {
        self.userHome = userHome
        self.temporaryDirectory = temporaryDirectory
        self.serverHome = serverHome
        self.bundledServer = bundledServer
        self.hostOverride = hostOverride
    }

    var baseEnvironment: [String: String] {
        [
            "HOME": userHome.path,
            "PATH": Self.systemPath,
            "TMPDIR": temporaryDirectory.path,
            "VESEL_SERVER_HOME": serverHome.root.path,
        ]
    }

    public func sync(uv: URL) -> Command {
        var environment = baseEnvironment
        environment["UV_PROJECT_ENVIRONMENT"] = serverHome.venv.path
        return Command(
            executable: uv,
            arguments: ["sync", "--frozen", "--no-dev", "--project", bundledServer.path],
            environment: environment
        )
    }

    public func setup() -> Command {
        var environment = baseEnvironment
        if let hostOverride {
            environment["VESEL_SERVER_HOST"] = hostOverride
        }
        return Command(
            executable: URL(filePath: "/bin/bash"),
            arguments: [bundledServer.appending(path: "setup.sh").path, "--qr-text"],
            environment: environment
        )
    }

    public func server() -> Command {
        var environment = baseEnvironment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        return Command(
            executable: serverHome.python,
            arguments: ["-m", "uvicorn"] + uvicornArguments + ["--app-dir", bundledServer.path],
            environment: environment
        )
    }

    /// The same arguments as after `uvicorn` in `server/launchd/app.vesel.server.plist`.
    public var uvicornArguments: [String] {
        [
            "vesel_server.app:create_app", "--factory",
            "--host", "0.0.0.0",
            "--port", String(Self.port),
            "--ssl-certfile", serverHome.certificate.path,
            "--ssl-keyfile", serverHome.privateKey.path,
            "--no-access-log",
            "--no-server-header",
        ]
    }
}
