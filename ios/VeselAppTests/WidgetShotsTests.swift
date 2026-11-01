import SwiftUI
import Testing
import VeselCore
import VeselStorage
import WidgetKit

/// Draws every widget in every state with `ImageRenderer`. The pictures go to the folder named by the
/// `VESEL_SHOTS_DIR` environment variable (pass `TEST_RUNNER_VESEL_SHOTS_DIR` to xcodebuild); without it only the
/// states are checked.
@MainActor
struct WidgetShotsTests {
    let now = at("2026-10-26T09:00:00Z")

    func entries() -> [(name: String, entry: VeselEntry)] {
        [
            ("normal", VeselEntry(date: now, snapshot: .sampleReady(at: now))),
            (
                "low",
                VeselEntry(
                    date: now, snapshot: .sampleReady(at: now, indicator: 2, subLevel: 20, asleepMinutes: 300, highMinutes: 48, hrv: 38, stressLevel: 75))
            ),
            ("long", VeselEntry(date: now, snapshot: .sampleReady(at: now, asleepMinutes: 600))),
            ("learning", VeselEntry(date: now, snapshot: .sampleReady(at: now, earlierNights: 3))),
            ("nodata", VeselEntry(date: now, snapshot: .empty)),
            ("stale", VeselEntry(date: now, snapshot: .sampleReady(at: now, syncedAgo: 14 * 3600))),
        ]
    }

    @Test func eachStateIsRecognised() {
        let byName = Dictionary(uniqueKeysWithValues: entries().map { ($0.name, $0.entry) })
        #expect(byName["normal"]?.content == .ready)
        #expect(byName["normal"]?.isStale == false)
        #expect(byName["normal"]?.updatedText == nil)
        #expect(byName["learning"]?.content == .learning(nights: 3))
        #expect(byName["learning"]?.learningText == "Your usual range appears after 7 nights · 3 of 7")
        #expect(byName["nodata"]?.content == .noData)
        #expect(byName["stale"]?.isStale == true)
        #expect(byName["stale"]?.updatedText?.hasPrefix("Updated ") == true)
    }

    @Test func staleUsesTheEntryDateNotTheClock() {
        let snapshot = WidgetSnapshot.sampleReady(at: now, syncedAgo: 0)
        #expect(!VeselEntry(date: now.addingTimeInterval(12 * 3600), snapshot: snapshot).isStale)
        #expect(VeselEntry(date: now.addingTimeInterval(13 * 3600), snapshot: snapshot).isStale)
    }

    @Test func aLowRecoveryTurnsTheLineWarm() {
        let low = WidgetSnapshot.sampleReady(at: now, indicator: 2, subLevel: 0).status
        let good = WidgetSnapshot.sampleReady(at: now, indicator: 4, subLevel: 0).status
        #expect(Theme.Palette.recoveryLine(low) == Theme.Palette.stress)
        #expect(Theme.Palette.recoveryLine(good) == Theme.Palette.recovery)
        #expect(Theme.Palette.recoveryLine(nil) == Theme.Palette.recovery)
    }

    @Test func drawsEveryWidgetInEveryState() throws {
        guard let path = ProcessInfo.processInfo.environment["VESEL_SHOTS_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, entry) in entries() {
            for scheme in [ColorScheme.light, .dark] {
                let suffix = scheme == .light ? "light" : "dark"
                try draw(
                    RecoveryRingSmallView(entry: entry), size: CGSize(width: 170, height: 170), home: true, scheme: scheme, to: directory,
                    "recovery-small-\(name)-\(suffix)")
                try draw(
                    StressNowView(entry: entry), size: CGSize(width: 170, height: 170), home: true, scheme: scheme, to: directory,
                    "stress-small-\(name)-\(suffix)")
                try draw(
                    TodayWidgetView(entry: entry), size: CGSize(width: 364, height: 170), home: true, scheme: scheme, to: directory,
                    "today-medium-\(name)-\(suffix)")
            }
            try draw(
                RecoveryRingCircularView(entry: entry), size: CGSize(width: 76, height: 76), home: false, scheme: .dark, to: directory,
                "recovery-circular-\(name)")
            try draw(SleepLockView(entry: entry), size: CGSize(width: 172, height: 76), home: false, scheme: .dark, to: directory, "sleep-rectangular-\(name)")
        }
        let tinted = VeselEntry(date: now, snapshot: .sampleReady(at: now))
        try draw(
            TodayWidgetView(entry: tinted).grayscale(1), size: CGSize(width: 364, height: 170), home: true, scheme: .dark, to: directory,
            "today-medium-grayscale")
        try draw(
            RecoveryRingCircularView(entry: tinted), size: CGSize(width: 76, height: 76), home: false, scheme: .dark, tint: .yellow, to: directory,
            "recovery-circular-tinted")
        try draw(
            SleepLockView(entry: tinted), size: CGSize(width: 172, height: 76), home: false, scheme: .dark, tint: .yellow, to: directory,
            "sleep-rectangular-tinted")
    }

    private func draw<V: View>(_ view: V, size: CGSize, home: Bool, scheme: ColorScheme, tint: Color? = nil, to directory: URL, _ name: String) throws {
        let framed = ZStack {
            if home {
                WidgetBackground()
            } else {
                LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
            }
            view
                .padding(home ? Theme.Spacing.s16 : 0)
                .foregroundStyle(home ? AnyShapeStyle(.primary) : AnyShapeStyle(tint ?? .white))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: home ? 24 : 12))
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 3
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: directory.appending(path: "\(name).png"))
    }
}

private func at(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}
