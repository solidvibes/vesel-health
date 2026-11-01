import Foundation
import Testing
import VeselBackupKit

struct RestartPolicyTests {
    let start = Date(timeIntervalSince1970: 1_793_000_000)

    @Test func theThirdExitWithinTenMinutesGivesUp() {
        var policy = RestartPolicy()
        let decisions = [0, 60, 9 * 60].map { policy.shouldRestart(afterExitAt: start.addingTimeInterval(TimeInterval($0))) }
        #expect(decisions == [true, true, false])
    }

    @Test func exitsOlderThanTenMinutesAreForgotten() {
        var policy = RestartPolicy()
        let decisions = [0, 5 * 60, 11 * 60].map { policy.shouldRestart(afterExitAt: start.addingTimeInterval(TimeInterval($0))) }
        #expect(decisions == [true, true, true])
    }

    @Test func resetStartsOver() {
        var policy = RestartPolicy()
        _ = policy.shouldRestart(afterExitAt: start)
        _ = policy.shouldRestart(afterExitAt: start)
        policy.reset()
        let again = policy.shouldRestart(afterExitAt: start)
        #expect(again)
    }
}
