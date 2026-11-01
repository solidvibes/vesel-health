import Foundation

/// What Today shows, decided from a few facts. A pure function so every state can be tested.
public struct TodayState: Sendable, Equatable {
    public enum Body: Sendable, Equatable {
        /// Skeletons and a "Reading last night…" pill: reading, and nothing for last night yet.
        case reading
        /// Can't reach the Loop; the numbers below are the last ones stored.
        case unreachable(lastRead: Date?)
        /// A read is waiting for the Loop to come near; the numbers below are the last ones stored.
        case waitingForLoop
        /// Fewer than 7 earlier nights: lines say "Learning your normal".
        case firstDay(nights: Int)
        case normal
        /// A band with no night stored at all.
        case noSleep
    }

    public enum MorningCard: Sendable, Equatable {
        case none
        /// "Good morning — I'm up".
        case goodMorning
        /// "Evaluating your night". `waitingForLoop`: a waiting "I'm up" tried and didn't find the Loop.
        case evaluating(waitingForLoop: Bool)
    }

    public var body: Body
    /// The card at the top of Today in the morning. Once last night is stored the morning is over, whatever the band says.
    public var morningCard: MorningCard
    /// The newest stored night isn't last night: Polar hasn't finished it, or the Loop wasn't worn.
    public var lastNightMissing: Bool
    /// Last night is missing and on its way: the band still records it, Polar is still finishing it, or it is being read.
    public var lastNightPending: Bool
    /// "Something's off": an alert went out today. Its card shows under the heart rate card, whatever the body shows.
    public var somethingOff: Bool

    /// `latestNight` is the newest night up to `today`. `bandStillRecordingSleep`: the band said it records sleep (or
    /// couldn't say) at the last read that reached it. `bandFinishingNight`: the band stopped recording sleep under 2 hours
    /// ago. `sleepEndedAt`: when the band was last seen to stop recording sleep. `imUp`: a kept "I'm up" tap.
    public init(
        sync: SyncStatus,
        bandStillRecordingSleep: Bool,
        bandFinishingNight: Bool,
        sleepEndedAt: Date?,
        dismissedGoodMorning: Bool,
        imUp: ImUpRequest?,
        latestNight: DayKey?,
        today: DayKey,
        now: Date,
        timeZone: TimeZone,
        earlierNights: Int,
        alertsToday: Int
    ) {
        somethingOff = alertsToday > 0
        let settled: Body = earlierNights < PersonalRange.minimumNights ? .firstDay(nights: earlierNights) : .normal
        let stored = latestNight == today
        let waiting = !stored && imUp?.isWaiting(at: now) == true
        let endedToday = sleepEndedAt.map { DayKey($0, in: timeZone) == today } ?? false
        let morning = MorningWindow.contains(now, in: timeZone) && !endedToday
        lastNightMissing = latestNight.map { $0 < today } ?? false
        lastNightPending = lastNightMissing && (waiting || bandStillRecordingSleep || bandFinishingNight || sync.isReading)
        if stored {
            morningCard = .none
        } else if waiting, let imUp {
            morningCard = .evaluating(waitingForLoop: imUp.missedLoop)
        } else if bandStillRecordingSleep || morning {
            // After "Still in bed" the night isn't over: no card.
            morningCard = dismissedGoodMorning ? .none : .goodMorning
        } else if lastNightPending {
            morningCard = .evaluating(waitingForLoop: false)
        } else {
            morningCard = .none
        }
        switch (sync, latestNight) {
        case (.reading, nil): body = .reading
        case (.reading, .some(let night)) where night < today: body = .reading
        case (.unreachable(let lastRead), _): body = .unreachable(lastRead: lastRead)
        case (.waitingForLoop, _): body = .waitingForLoop
        case (_, nil): body = .noSleep
        default: body = settled
        }
    }
}
