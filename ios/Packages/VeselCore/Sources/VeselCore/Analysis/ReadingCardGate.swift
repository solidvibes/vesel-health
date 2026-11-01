import Foundation

/// Whether Today shows the reading list. Only the first read after the app comes to the foreground gets it, and only once that
/// read has run for `delay`. A later read (the 5-minute ones) or a background read never does; the card shows once and folds away.
public struct ReadingCardGate: Sendable, Equatable {
    public static let delay: Duration = .seconds(1)

    private enum Stage { case waitingForRead, readStarted, shown, used }
    private var stage: Stage

    public init(isReading: Bool = false) {
        stage = isReading ? .readStarted : .waitingForRead
    }

    public var isShown: Bool { stage == .shown }
    /// A read that may still earn the card has started and `delay` has not passed.
    public var isWaiting: Bool { stage == .readStarted }
    /// Today follows the read (its reading state) only while this read may earn the card or has it; any other read leaves Today as it is.
    public var followsRead: Bool { stage == .readStarted || stage == .shown }

    /// The app came to the foreground: the next read, or the one already running, may earn the card. A card already showing stays.
    public mutating func cameToForeground(isReading: Bool) {
        guard !(isShown && isReading) else { return }
        self = ReadingCardGate(isReading: isReading)
    }

    public mutating func readingChanged(_ isReading: Bool) {
        switch (stage, isReading) {
        case (.waitingForRead, true): stage = .readStarted
        case (.readStarted, false), (.shown, false): stage = .used
        default: break
        }
    }

    /// The read is still running `delay` after it started.
    public mutating func delayPassed() {
        if stage == .readStarted { stage = .shown }
    }
}
