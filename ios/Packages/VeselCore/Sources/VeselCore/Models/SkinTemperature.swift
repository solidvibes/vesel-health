import Foundation

public struct SkinTemperatureSample: Sendable, Equatable {
    public var time: Date
    public var celsius: Double

    public init(time: Date, celsius: Double) {
        self.time = time
        self.celsius = celsius
    }
}
