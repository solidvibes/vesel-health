import Foundation
import Testing
import VeselCore

struct PPICleaningTests {
    let start = at("2026-10-26T09:00:00Z")

    @Test func aBeatWithTheBlockerOnOrWithoutSkinContactIsDroppedAndCountedOnce() {
        let blocked = PPICleaning.clean(beats([1000, 1010, 1020, 1030], start: start, flagged: [1]))
        #expect(blocked.kept.map(\.intervalMs) == [1000, 1020, 1030])
        #expect(blocked.counts.flagged == 1)
        #expect(blocked.counts.kept == 3)
        let noSkin = PPICleaning.clean(beats([1000, 1010, 1020], start: start, noSkin: [0, 2]))
        #expect(noSkin.kept.map(\.intervalMs) == [1010])
        #expect(noSkin.counts.flagged == 2)
        let both = PPICleaning.clean(beats([1000, 1010], start: start, flagged: [0], noSkin: [0]))
        #expect(both.counts.flagged == 1)
        #expect(both.counts.intervals == 2)
    }

    @Test func beatsOutsideThreeHundredToTwoThousandAreDropped() {
        // 299 and 2001 go; 300 and 2000 stay. 300 → 2000 is a jump of 567 %, so the 2000 is dropped as a jump, not as out of range.
        let result = PPICleaning.clean(beats([299, 300, 2001, 2000], start: start))
        #expect(result.kept.map(\.intervalMs) == [300])
        #expect(result.counts.outOfRange == 2)
        #expect(result.counts.jumps == 1)
        #expect(PPICleaning.clean(beats([2000], start: start)).kept.count == 1)
    }

    @Test func aJumpOverTwentyPercentFromThePreviousValidBeatIsDropped() {
        // 900 → 1100 is 22.2 %: dropped. 950 is compared with 900 (the last valid one), 5.6 %: kept.
        let result = PPICleaning.clean(beats([800, 900, 1100, 950], start: start))
        #expect(result.kept.map(\.intervalMs) == [800, 900, 950])
        #expect(result.counts.jumps == 1)
        // Exactly 20 % stays.
        let edge = PPICleaning.clean(beats([1000, 1200, 960], start: start))
        #expect(edge.kept.map(\.intervalMs) == [1000, 1200, 960])
        #expect(edge.counts.jumps == 0)
    }

    @Test func theFirstValidBeatHasNothingToJumpFrom() {
        let result = PPICleaning.clean(beats([500, 1000, 1010], start: start, flagged: [0]))
        #expect(result.kept.map(\.intervalMs) == [1000, 1010])
    }

    @Test func everyDroppedBeatIsCountedOnce() {
        // flagged 1; 250 out of range; 1500 is a 50 % jump from 1000; 1000 and 1010 stay.
        let result = PPICleaning.clean(beats([1000, 5000, 250, 1500, 1010], start: start, flagged: [1]))
        #expect(result.counts.intervals == 5)
        #expect(result.counts.flagged == 1)
        #expect(result.counts.outOfRange == 1)
        #expect(result.counts.jumps == 1)
        #expect(result.counts.kept == 2)
    }
}
