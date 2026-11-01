import Testing
import VeselCore

struct ReadingCardGateTests {
    @Test func aFastFirstReadNeverShowsTheCard() {
        var gate = ReadingCardGate()
        gate.readingChanged(true)
        #expect(gate.isWaiting && !gate.isShown)
        gate.readingChanged(false)
        gate.delayPassed()
        #expect(!gate.isShown && !gate.isWaiting)
    }

    @Test func aSlowFirstReadShowsOnceThenFoldsAway() {
        var gate = ReadingCardGate()
        gate.readingChanged(true)
        gate.delayPassed()
        #expect(gate.isShown)
        gate.readingChanged(false)
        #expect(!gate.isShown)
        gate.readingChanged(true)
        gate.delayPassed()
        #expect(!gate.isShown && !gate.isWaiting)
    }

    @Test func aLaterReadWhileTheAppStaysOpenNeverShowsIt() {
        var gate = ReadingCardGate()
        gate.readingChanged(true)
        gate.readingChanged(false)
        gate.readingChanged(true)
        gate.delayPassed()
        #expect(!gate.isShown)
    }

    @Test func comingToTheForegroundArmsTheNextReadOrTheOneRunning() {
        var gate = ReadingCardGate()
        gate.readingChanged(true)
        gate.readingChanged(false)
        gate.cameToForeground(isReading: false)
        gate.readingChanged(true)
        gate.delayPassed()
        #expect(gate.isShown)
        gate.readingChanged(false)

        gate.cameToForeground(isReading: true)
        #expect(gate.isWaiting)
        gate.delayPassed()
        #expect(gate.isShown)
    }

    @Test func onlyTheReadThatMayEarnTheCardChangesToday() {
        var gate = ReadingCardGate()
        #expect(!gate.followsRead)
        gate.readingChanged(true)
        #expect(gate.followsRead)
        gate.delayPassed()
        #expect(gate.followsRead)
        gate.readingChanged(false)
        gate.readingChanged(true)
        #expect(!gate.followsRead)
    }

    @Test func aCardShowingWhenTheAppLeftStaysWhenItComesBackMidRead() {
        var gate = ReadingCardGate()
        gate.readingChanged(true)
        gate.delayPassed()
        gate.cameToForeground(isReading: true)
        #expect(gate.isShown)
        gate.readingChanged(false)
        gate.cameToForeground(isReading: false)
        #expect(!gate.isShown && !gate.followsRead)
    }
}
