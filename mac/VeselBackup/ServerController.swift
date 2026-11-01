import Darwin
import Foundation
import Observation
import SystemConfiguration
import VeselBackupKit

enum Problem: Equatable {
    case uvMissing
    case portBusy
    case keepsStopping
}

enum ServerState: Equatable {
    case notPaired
    case off
    case starting
    case on
    case problem(Problem)
    case terminalSetup
}

enum PairingOutcome {
    /// Holds the token: keep it in view state only, never log, store or copy it.
    case code(PairingCode)
    case failed(String)
}

/// Runs the backup server as a child process while the app is open.
@MainActor @Observable
final class ServerController {
    var state: ServerState = .notPaired
    var stats: BackupStats = .empty
    private(set) var serverOn: Bool

    let config: AppConfig
    private var process: Process?
    private var task: Task<Void, Never>?
    /// Bumped by every transition; an older transition stops at its next step.
    private var generation = 0
    private var restartPolicy = RestartPolicy()
    private let now: () -> Date

    init(config: AppConfig, now: @escaping () -> Date = Date.init) {
        self.config = config
        self.now = now
        serverOn = config.defaults.object(forKey: "serverOn") as? Bool ?? true
    }

    var host: String {
        if let override = config.launch.hostOverride {
            return override
        }
        let name = SCDynamicStoreCopyLocalHostName(nil) as String? ?? "this Mac"
        return "\(name).local"
    }

    var isPaired: Bool { config.serverHome.isPaired }

    func launch() {
        transition { controller, generation in
            await controller.evaluate(generation)
        }
    }

    func setServerOn(_ on: Bool) {
        serverOn = on
        config.defaults.set(on, forKey: "serverOn")
        restartPolicy.reset()
        transition { controller, generation in
            if on {
                await controller.evaluate(generation)
            } else {
                await controller.stopServer()
                if controller.generation == generation { controller.state = .off }
            }
        }
    }

    func tryAgain() {
        restartPolicy.reset()
        launch()
    }

    func refreshStats() {
        let database = config.serverHome.database
        Task {
            stats = await Self.readStats(database)
        }
    }

    /// Runs the bundled `setup.sh --qr-text`: a new token, the certificate kept. Restarts the server so it reads the new token.
    func pair() async -> PairingOutcome {
        guard !DaemonCheck.isInstalled(plist: config.daemonPlist) else {
            return .failed("The Terminal set-up runs the backup on this Mac.")
        }
        let result = await Self.runCapturingOutput(config.launch.setup())
        guard result.status == 0, let code = PairingCode.parse(result.output) else {
            return .failed(result.lastErrorLine)
        }
        serverOn = true
        config.defaults.set(true, forKey: "serverOn")
        restartPolicy.reset()
        transition { controller, generation in
            await controller.start(generation)
        }
        return .code(code)
    }

    /// Off switch, Quit, logout: SIGTERM, up to 3 s, then SIGKILL.
    func stop() async {
        generation += 1
        task?.cancel()
        await stopServer()
    }

    // MARK: - Transitions

    private func transition(_ work: @escaping @MainActor (ServerController, Int) async -> Void) {
        generation += 1
        let generation = generation
        task?.cancel()
        task = Task { await work(self, generation) }
    }

    private func evaluate(_ generation: Int) async {
        if DaemonCheck.isInstalled(plist: config.daemonPlist) {
            await stopServer()
            state = .terminalSetup
        } else if !config.serverHome.isPaired {
            state = .notPaired
        } else if !serverOn {
            state = .off
        } else {
            await start(generation)
        }
    }

    private func start(_ generation: Int) async {
        await stopServer()
        guard generation == self.generation else { return }
        state = .starting
        let home = config.serverHome
        try? home.sweepPermissions()

        guard let uv = UVLocator.locate(userHome: config.userHome) else {
            state = .problem(.uvMissing)
            return
        }
        let synced = await Self.runToLog(config.launch.sync(uv: uv), log: home.log, timeout: .seconds(300))
        guard generation == self.generation else { return }
        guard synced else {
            state = .problem(.keepsStopping)
            return
        }
        try? home.sweepPermissions()

        if await PortProbe.isOpen(port: ServerLaunch.port) {
            guard await replaceOrphan(), generation == self.generation else {
                if generation == self.generation { state = .problem(.portBusy) }
                return
            }
        }
        guard generation == self.generation else { return }

        let spawned: Process
        do {
            spawned = try spawn(config.launch.server(), log: home.log)
        } catch {
            state = .problem(.keepsStopping)
            return
        }
        process = spawned
        try? home.writePid(spawned.processIdentifier)

        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            guard generation == self.generation, process === spawned else { return }
            if await PortProbe.isOpen(port: ServerLaunch.port) {
                state = .on
                return
            }
        }
        guard generation == self.generation, process === spawned else { return }
        await stopServer()
        state = .problem(.keepsStopping)
    }

    private func serverExited(_ exited: Process) {
        guard exited === process else { return }
        process = nil
        config.serverHome.removePid()
        guard restartPolicy.shouldRestart(afterExitAt: now()) else {
            generation += 1
            state = .problem(.keepsStopping)
            return
        }
        state = .starting
        transition { controller, generation in
            try? await Task.sleep(for: RestartPolicy.delay)
            guard generation == controller.generation else { return }
            await controller.start(generation)
        }
    }

    private func stopServer() async {
        guard let running = process else { return }
        process = nil
        config.serverHome.removePid()
        await Self.terminate(running)
    }

    /// A server left behind by a crash of this app: its pid file names a live process running our venv's Python
    /// that started before the pid file was written. The venv's Python resolves to uv's shared interpreter, so the
    /// start time is what tells our server apart from another process that later got the same pid.
    private func replaceOrphan() async -> Bool {
        guard let pid = config.serverHome.readPid(), pid > 0,
            let written = try? config.serverHome.pidFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            let started = Self.startTime(of: pid), started <= written,
            let running = Self.executablePath(of: pid),
            let ours = Self.realPath(config.serverHome.python),
            running == ours
        else { return false }
        kill(pid, SIGTERM)
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if await !PortProbe.isOpen(port: ServerLaunch.port) {
                config.serverHome.removePid()
                return true
            }
        }
        return false
    }

    private func spawn(_ command: Command, log: URL) throws -> Process {
        let output = try Self.appendHandle(log)
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = config.serverHome.root
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { [weak self] exited in
            Task { @MainActor in self?.serverExited(exited) }
        }
        try process.run()
        return process
    }

    // MARK: - Off the main thread

    @concurrent
    private static func readStats(_ database: URL) async -> BackupStats {
        (try? BackupStats.read(database: database)) ?? .empty
    }

    @concurrent
    private static func terminate(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if !process.isRunning { return }
        }
        kill(process.processIdentifier, SIGKILL)
    }

    /// Runs a command with stdout and stderr appended to the server log. False on failure or timeout.
    @concurrent
    private static func runToLog(_ command: Command, log: URL, timeout: Duration) async -> Bool {
        guard let output = try? appendHandle(log) else { return false }
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return false
        }
        let deadline = ContinuousClock.now + timeout
        while process.isRunning {
            if ContinuousClock.now > deadline {
                process.terminate()
                return false
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return process.terminationStatus == 0
    }

    struct CapturedRun {
        let status: Int32
        /// The QR text: lives only in memory.
        let output: String
        let lastErrorLine: String
    }

    @concurrent
    private static func runCapturingOutput(_ command: Command) async -> CapturedRun {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return CapturedRun(status: -1, output: "", lastErrorLine: "Couldn't run setup.sh.")
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let lastError =
            String(decoding: errorData, as: UTF8.self)
            .split(separator: "\n")
            .last
            .map(String.init) ?? ""
        return CapturedRun(status: process.terminationStatus, output: String(decoding: outputData, as: UTF8.self), lastErrorLine: lastError)
    }

    private nonisolated static func appendHandle(_ url: URL) throws -> FileHandle {
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private nonisolated static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private nonisolated static func startTime(of pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    private nonisolated static func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

enum PortProbe {
    /// True when something accepts a TCP connection on 127.0.0.1.
    @concurrent
    static func isOpen(port: UInt16) async -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
