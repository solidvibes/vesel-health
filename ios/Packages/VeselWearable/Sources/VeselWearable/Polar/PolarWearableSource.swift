import Foundation
@preconcurrency import PolarBleSdk
import VeselCore

/// The Polar Loop over Bluetooth, through the Polar BLE SDK. Every SDK call goes through this actor,
/// so calls to the band never overlap. The band is never put into SDK mode.
public actor PolarWearableSource: WearableSource {
    private let api: PolarBleApi
    private let bandEvents: PolarBandEvents
    private let clock: any VeselClock
    private var deviceId: String?
    /// The band's workouts as last listed, by session, for reading one.
    private var trainingSessions: [String: PolarTrainingSessionReference] = [:]

    public init(clock: any VeselClock) {
        var api = PolarBleApiDefaultImpl.polarImplementation(
            DispatchQueue(label: "app.vesel.polar"),
            features: [
                .feature_hr,
                .feature_device_info,
                .feature_battery_info,
                .feature_polar_device_time_setup,
                .feature_polar_activity_data,
                .feature_polar_sleep_data,
                .feature_polar_temperature_data,
                .feature_polar_online_streaming,
                .feature_polar_device_control,
                .feature_polar_file_transfer,
                .feature_polar_training_data,
            ],
            restoreIdentifier: "app.vesel.ios.central"
        )
        api.automaticReconnection = true
        let bandEvents = PolarBandEvents(clock: clock)
        api.observer = bandEvents
        api.deviceInfoObserver = bandEvents
        api.powerStateObserver = bandEvents
        self.api = api
        self.bandEvents = bandEvents
        self.clock = clock
    }

    public var connectionState: ConnectionState { bandEvents.state }

    public var drops: Int { bandEvents.drops }

    public nonisolated var events: AsyncStream<BandEvent> { bandEvents.stream }

    public nonisolated var links: AsyncStream<BandLink> { bandEvents.links }

    public func connect(_ deviceId: String) {
        self.deviceId = deviceId
        try? api.connectToDevice(deviceId)
    }

    public func reachable(within wait: Duration) async -> Bool {
        guard let deviceId else { return false }
        // After a drop the SDK's own reconnection can give up; asking again is a no-op while a connection is open or opening.
        if bandEvents.state != .connected { try? api.connectToDevice(deviceId) }
        let deadline = ContinuousClock.now + wait
        if await waitUntilReady(deviceId, until: min(deadline, .now + .seconds(3))) { return true }
        // After iOS relaunches Vesel, the SDK can restore the Loop's link without ever reporting it, so asking again is a
        // no-op and nothing is heard: close that link by its address and open it afresh, which the SDK does report.
        if bandEvents.state == .disconnected, !Task.isCancelled {
            if let address = bandEvents.address { try? api.disconnectFromDevice(address) }
            try? api.disconnectFromDevice(deviceId)
            try? await Task.sleep(for: .seconds(1))
            try? api.connectToDevice(deviceId)
        }
        return await waitUntilReady(deviceId, until: deadline)
    }

    public func pair() async throws -> PairedBand {
        let found = try await scan(for: .seconds(8))
        guard let strongest = found.max(by: { $0.rssi < $1.rssi }) else { throw PairingError.notFound }
        bandEvents.reset()
        deviceId = strongest.deviceId
        do {
            try api.connectToDevice(strongest.deviceId)
        } catch {
            throw PairingError.refused
        }
        // Long enough for the owner to read and accept the iOS pairing prompt.
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            if bandEvents.pairingRefused { throw PairingError.refused }
            if bandEvents.state == .connected, api.isFeatureReady(strongest.deviceId, feature: .feature_polar_file_transfer) {
                return PairedBand(deviceId: strongest.deviceId, name: strongest.name)
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw PairingError.refused
    }

    public func cancelPairing() {
        if let deviceId, bandEvents.state != .connected {
            try? api.disconnectFromDevice(deviceId)
            self.deviceId = nil
        }
    }

    public func firstTimeUse(_ profile: Profile, now: Date) async throws {
        let id = try ready()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZone
        let age = calendar.component(.year, from: now) - profile.birthYear
        let deviceTime = ISO8601DateFormatter()
        deviceTime.formatOptions = [.withInternetDateTime]
        deviceTime.timeZone = TimeZone(secondsFromGMT: 0)
        let config = PolarFirstTimeUseConfig(
            gender: profile.sex == .male ? .male : .female,
            birthDate: Calendar.current.date(from: DateComponents(year: profile.birthYear, month: 1, day: 1, hour: 12))!,
            height: Float(profile.heightCm),
            weight: Float(profile.weightKg),
            maxHeartRate: PolarDefaults.maxHeartRate(age: age),
            vo2Max: PolarDefaults.vo2Max(age: age, sex: profile.sex),
            restingHeartRate: PolarDefaults.restingHeartRate,
            trainingBackground: .occasional,
            deviceTime: deviceTime.string(from: now),
            typicalDay: .mostlySitting,
            sleepGoalMinutes: profile.sleepGoalMinutes
        )
        do {
            try await api.doFirstTimeUse(id, ftuConfig: config)
        } catch {
            throw PairingError.setupFailed
        }
    }

    public func setWrist(_ wrist: WristSide) async throws {
        let location: PolarUserDeviceSettings.DeviceLocation = wrist == .left ? .WRIST_LEFT : .WRIST_RIGHT
        do {
            try await api.setUserDeviceLocation(try ready(), location: location.toInt())
        } catch {
            throw BandWriteError.refused
        }
    }

    public func startSync() async throws {
        try await api.sendInitializationAndStartSyncNotifications(identifier: try ready())
    }

    public func stopSync() async throws {
        try await api.sendTerminateAndStopSyncNotifications(identifier: try ready())
    }

    public func setTime(_ date: Date, zone: TimeZone) async throws {
        try await api.setLocalTime(try ready(), time: date, zone: zone)
    }

    public func battery() throws -> Int {
        try api.getBatteryLevel(identifier: try ready())
    }

    public func diskSpace() async throws -> DiskSpace {
        let space = try await api.getDiskSpace(try ready())
        return DiskSpace(freeBytes: Int64(space.freeSpace), totalBytes: Int64(space.totalSpace))
    }

    public func sleepRecordingStatus() async throws -> SleepRecordingStatus {
        switch try await api.getSleepRecordingStatus(identifier: try ready()) {
        case .enabled: .recording
        case .disabled: .stopped
        case .unknown: .unknown
        }
    }

    public func endSleepRecording() async throws {
        try await api.stopSleepRecording(identifier: try ready())
    }

    /// The SDK names day folders inconsistently: 24/7 files and skin temperature by UTC date, the rest by the
    /// phone's local date. Noon of the day in the matching zone names the same day either way.
    public func fetch(_ kind: FetchKind, from start: DayKey, through end: DayKey, answered: @escaping @Sendable () async -> Void) async throws -> [BandPayload]
    {
        let id = try ready()
        let zone = clock.timeZone
        let days = Self.days(from: start, through: end)
        let utc = TimeZone(identifier: "UTC")!

        switch kind {
        case .heartRate:
            let results = try await api.get247HrSamples(identifier: id, fromDate: Self.noon(start, in: utc), toDate: Self.noon(end, in: utc))
            let byDay = Dictionary(grouping: results) { PolarMapping.dayKey($0.date) }
            return try days.map { try PolarMapping.heartRates(byDay[$0] ?? [], day: $0, zone: zone) }
        case .ppi:
            let results = try await api.get247PPiSamples(identifier: id, fromDate: Self.noon(start, in: utc), toDate: Self.noon(end, in: utc))
            let byDay = Dictionary(grouping: results) { PolarMapping.dayKey($0.date) }
            return try days.map { try PolarMapping.ppi(byDay[$0] ?? [], day: $0, zone: zone) }
        default:
            var payloads: [BandPayload] = []
            for day in days {
                payloads.append(try await fetchOneDay(kind, day: day, id: id, zone: zone))
                await answered()
            }
            return payloads
        }
    }

    private func fetchOneDay(_ kind: FetchKind, day: DayKey, id: String, zone: TimeZone) async throws -> BandPayload {
        let local = Self.noon(day, in: zone)
        let utc = Self.noon(day, in: TimeZone(identifier: "UTC")!)
        switch kind {
        case .sleep:
            let result = try await api.getSleep(identifier: id, fromDate: local, toDate: local).first
            return try PolarMapping.sleep(result, day: day, zone: zone)
        case .nightlyRecharge:
            let result = try await api.getNightlyRecharge(identifier: id, fromDate: local, toDate: local).first
            return try PolarMapping.recharge(result, day: day, zone: zone)
        case .skinTemperature:
            let result = try await api.getSkinTemperature(identifier: id, fromDate: utc, toDate: utc).first
            return try PolarMapping.skinTemperature(result, day: day, zone: zone)
        case .activitySamples:
            let result = try await api.getActivitySampleData(identifier: id, fromDate: local, toDate: local).first
            return try PolarMapping.activitySamples(result, day: day, zone: zone)
        case .dailySummary:
            let result = try await api.getDailySummaryData(identifier: id, fromDate: local, toDate: local).first
            return try PolarMapping.dailySummary(result, day: day, zone: zone)
        case .heartRate, .ppi:
            // `fetch` reads these kinds for the whole range before it reaches the per-day loop.
            preconditionFailure("24/7 data is fetched for the whole range at once")
        }
    }

    public func deleteStored(_ type: StoredDataType, until day: DayKey) async throws {
        let polarType: PolarStoredDataType.StoredDataType =
            switch type {
            case .sleep: .SLEEP
            case .nightlyRecharge: .NIGHTLY_RECOVERY
            case .autoSample: .AUTO_SAMPLE
            case .skinTemperature: .SKINTEMP
            case .activity: .ACTIVITY
            case .dailySummary: .DAILY_SUMMARY
            }
        try await api.deleteStoredDeviceData(try ready(), dataType: polarType, until: ClearPlan.until(day))
    }

    public func factoryReset() async throws {
        try await api.doFactoryReset(try ready())
        deviceId = nil
    }

    public func workoutDetection() async throws -> WorkoutDetection? {
        let settings = try await api.getPolarUserDeviceSettings(identifier: try ready())
        guard let mode = settings.automaticTrainingDetectionMode else { return nil }
        return WorkoutDetection(
            isOn: mode == .ON,
            sensitivity: Int(settings.automaticTrainingDetectionSensitivity ?? 50),
            minimumMinutes: Int((Double(settings.minimumTrainingDurationSeconds ?? 600) / 60).rounded())
        )
    }

    /// Reads the band's settings and rewrites only training detection; never `setPolarUserDeviceSettings`, which rebuilds them.
    public func setWorkoutDetection(_ detection: WorkoutDetection) async throws {
        try await api.setAutomaticTrainingDetectionSettings(
            try ready(), mode: detection.isOn, sensitivity: detection.sensitivity, minimumDuration: detection.minimumMinutes * 60
        )
    }

    public func workoutStatus() async throws -> WorkoutStatus {
        let info = try await api.getExerciseStatus(identifier: try ready())
        return info.status == .inProgress || info.status == .paused ? .running(since: info.startTime) : .notRunning
    }

    public func workoutReferences() async throws -> [WorkoutReference] {
        let references = try await api.getTrainingSessionReferences(identifier: try ready(), fromDate: nil, toDate: nil)
        trainingSessions = [:]
        return references.compactMap { reference in
            guard let session = PolarMapping.workoutSession(reference.path) else { return nil }
            trainingSessions[session] = reference
            return WorkoutReference(session: session, date: reference.date, fileSize: reference.fileSize)
        }
    }

    public func workout(_ reference: WorkoutReference) async throws -> BandWorkout {
        guard let polar = trainingSessions[reference.session] else { throw WorkoutReadError.notListed }
        let session = try await api.getTrainingSession(identifier: try ready(), trainingSessionReference: polar)
        return try PolarMapping.workout(session, zone: clock.timeZone)
    }

    public func watchBand() async {
        guard let id = try? ready() else { return }
        await bandEvents.watch(api, deviceId: id, timeout: .seconds(10))
    }

    public func startLiveHeartRate() throws -> AsyncThrowingStream<LiveHeartRate, Error> {
        let samples = api.startHrStreaming(try ready())
        let clock = clock
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await data in samples {
                        guard let last = data.last else { continue }
                        continuation.yield(
                            LiveHeartRate(
                                bpm: Int(last.hr),
                                skinContact: last.contactStatusSupported ? last.contactStatus : nil,
                                time: clock.now
                            ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stopLiveHeartRate() async {
        guard let deviceId else { return }
        try? await api.stopHrStreaming(deviceId)
    }

    private func ready() throws -> String {
        guard let deviceId, bandEvents.state == .connected else { throw PairingError.notFound }
        return deviceId
    }

    private func waitUntilReady(_ deviceId: String, until deadline: ContinuousClock.Instant) async -> Bool {
        while true {
            if bandEvents.state == .connected, api.isFeatureReady(deviceId, feature: .feature_polar_file_transfer) { return true }
            guard ContinuousClock.now < deadline, (try? await Task.sleep(for: .milliseconds(250))) != nil else { return false }
        }
    }

    private func scan(for duration: Duration) async throws -> [PolarDeviceInfo] {
        let stream = api.searchForDevice(withNameContaining: "Loop")
        let collector = Task { () -> [PolarDeviceInfo] in
            var found: [String: PolarDeviceInfo] = [:]
            do {
                for try await info in stream where info.connectable {
                    found[info.deviceId] = info
                }
            } catch {}
            return Array(found.values)
        }
        defer { collector.cancel() }
        try await Task.sleep(for: duration)
        collector.cancel()
        return await collector.value
    }

    private static func noon(_ day: DayKey, in zone: TimeZone) -> Date {
        day.start(in: zone).addingTimeInterval(12 * 3600)
    }

    private static func days(from start: DayKey, through end: DayKey) -> [DayKey] {
        var days: [DayKey] = []
        var day = start
        while day <= end {
            days.append(day)
            day = day.adding(days: 1)
        }
        return days
    }
}
