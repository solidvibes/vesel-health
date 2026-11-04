import Testing
import VeselCore

struct WorkoutHeartRatesTests {
    @Test func shortWorkoutUsesFiveSecondBuckets() throws {
        let rates = WorkoutHeartRates(intervalMs: 1000, bpm: [100, 102, 104, 106, 108, 110, 112, 114, 116, 118])
        let averaged = try #require(rates.averaged())
        #expect(averaged.bucketSeconds == 5)
        #expect(averaged.points == [.init(offsetSeconds: 2.5, bpm: 104), .init(offsetSeconds: 7.5, bpm: 114)])
    }

    @Test func longWorkoutGetsAboutOneHundredTwentyPoints() throws {
        let bpm = (0..<4500).map { 120 + $0 % 2 * 10 }
        let averaged = try #require(WorkoutHeartRates(intervalMs: 1000, bpm: bpm).averaged())
        #expect(averaged.bucketSeconds == 38)
        #expect(averaged.points.count == 119)
        #expect(averaged.points[0] == .init(offsetSeconds: 19, bpm: 125))
    }

    @Test func aGapStaysAGap() throws {
        let bpm = Array(repeating: 100, count: 5) + Array(repeating: 0, count: 5) + Array(repeating: 120, count: 5)
        let averaged = try #require(WorkoutHeartRates(intervalMs: 1000, bpm: bpm).averaged())
        #expect(averaged.points == [.init(offsetSeconds: 2.5, bpm: 100), .init(offsetSeconds: 12.5, bpm: 120)])
    }

    @Test func nothingToAverage() {
        #expect(WorkoutHeartRates(intervalMs: 1000, bpm: []).averaged() == nil)
        #expect(WorkoutHeartRates(intervalMs: 0, bpm: [100]).averaged() == nil)
    }
}
