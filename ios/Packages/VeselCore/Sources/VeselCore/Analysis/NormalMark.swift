/// How one reading stands against your normal, in four marks. Colour is never the only sign: each has a symbol and words.
public enum NormalMark: Sendable, Equatable {
    public enum Side: Sendable, Equatable {
        case above, below
    }

    /// Which side of your normal is the better one, where there is one.
    public enum Better: Sendable, Equatable {
        case higher, lower, neither
    }

    case inside
    /// Outside, on the better side, at any distance.
    case better(Side)
    /// Outside, on the side that matters.
    case off(Side)
    /// Well outside, on the side that matters.
    case far(Side)

    /// Nil while learning.
    public init?(verdict: RangeVerdict, better: Better) {
        switch verdict {
        case .learning: return nil
        case .usual: self = .inside
        case .higher, .wellAbove:
            self = better == .higher ? .better(.above) : (verdict == .wellAbove ? .far(.above) : .off(.above))
        case .lower, .wellBelow:
            self = better == .lower ? .better(.below) : (verdict == .wellBelow ? .far(.below) : .off(.below))
        }
    }

    /// Polar's 1 to 6: 4 and up is inside, 3 is below, 1 and 2 well below.
    public init(recovery indicator: Int) {
        if indicator >= InRange.recoveryInside {
            self = .inside
        } else {
            self = indicator == 3 ? .off(.below) : .far(.below)
        }
    }

    public var isOutside: Bool { self != .inside }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .inside: "checkmark"
        case .far: "exclamationmark.2"
        case .better(let side), .off(let side): side == .above ? "arrow.up" : "arrow.down"
        }
    }

    public var words: String {
        switch self {
        case .inside: "inside your normal"
        case .better(let side): "\(side.word) your normal, the good side"
        case .off(let side): "\(side.word) your normal"
        case .far(let side): "well \(side.word) your normal"
        }
    }
}

extension NormalMark.Side {
    fileprivate var word: String { self == .above ? "above" : "below" }
}
