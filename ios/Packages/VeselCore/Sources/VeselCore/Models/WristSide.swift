import Foundation

/// Which wrist the Loop is worn on. Polar's sleep and activity maths are tuned to it.
public enum WristSide: String, Sendable, CaseIterable {
    case left, right
}
