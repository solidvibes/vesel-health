import Foundation
import Testing
import VeselCore

struct SyncProgressTests {
    @Test func aReadWithTheNightTicksEachPart() {
        let steps: [SyncStep] = [
            .loopFound, .kinds([.sleep, .nightlyRecharge, .heartRate, .ppi, .skinTemperature]),
            .fetched(.sleep), .fetched(.nightlyRecharge), .fetched(.heartRate), .fetched(.ppi), .fetched(.skinTemperature),
        ]
        let progress = steps.reduce(SyncProgress()) { $0.applying($1) }
        #expect(progress == SyncProgress(loopFound: true, heartRate: true, nightParts: 3, nightPartsTotal: 3))
        #expect(SyncStatus.reading(progress).isReading)
        #expect(!SyncStatus.idle.isReading)
    }

    @Test func whileTheBandStillRecordsTheNightTheNightRowIsLeftOut() {
        let steps: [SyncStep] = [.loopFound, .kinds([.heartRate, .ppi, .skinTemperature]), .fetched(.heartRate), .fetched(.skinTemperature)]
        let progress = steps.reduce(SyncProgress()) { $0.applying($1) }
        #expect(progress == SyncProgress(loopFound: true, heartRate: true, nightParts: 0, nightPartsTotal: 0))
    }
}
