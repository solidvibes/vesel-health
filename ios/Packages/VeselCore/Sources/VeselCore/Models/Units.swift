import Foundation

/// How the screens write weight, height, waist and skin temperature. Stored values are always metric.
public enum Units: String, Sendable, CaseIterable {
    case metric, us

    public static let poundsPerKilogram = 2.20462
    public static let centimetresPerInch = 2.54
    public static let metresPerMile = 1609.344

    /// "75 kg" / "165 lb"
    public func weightText(kg: Double) -> String {
        "\(Int(weight(kg: kg).rounded())) \(self == .metric ? "kg" : "lb")"
    }

    /// "180 cm" / "5 ft 11 in"
    public func heightText(cm: Double) -> String {
        if self == .metric { return "\(Int(cm.rounded())) cm" }
        let (feet, inches) = Self.feetAndInches(cm: cm)
        return "\(feet) ft \(inches) in"
    }

    /// "84 cm" / "33 in"
    public func waistText(cm: Double) -> String {
        "\(Int(length(cm: cm).rounded())) \(self == .metric ? "cm" : "in")"
    }

    public var temperatureUnit: String { self == .metric ? "°C" : "°F" }

    /// "34.6 °C" / "94.3 °F"
    public func temperatureText(celsius: Double) -> String {
        "\(NumberText.decimal(temperature(celsius: celsius), 1)) \(temperatureUnit)"
    }

    /// "+0.2 °C" / "+0.4 °F"
    public func temperatureDifferenceText(celsius: Double) -> String {
        let difference = temperatureDifference(celsius: celsius)
        return "\(difference >= 0 ? "+" : "−")\(NumberText.decimal(abs(difference), 1)) \(temperatureUnit)"
    }

    /// A route's length: "8.4 km" / "5.2 mi".
    public func distanceText(meters: Double) -> String {
        self == .metric ? "\(NumberText.decimal(meters / 1000, 1)) km" : "\(NumberText.decimal(meters / Self.metresPerMile, 1)) mi"
    }

    /// An average speed: "11.9 km/h" / "7.4 mph".
    public func speedText(kmh: Double) -> String {
        self == .metric ? "\(NumberText.decimal(kmh, 1)) km/h" : "\(NumberText.decimal(kmh * 1000 / Self.metresPerMile, 1)) mph"
    }

    /// Kilograms or pounds.
    public func weight(kg: Double) -> Double {
        self == .metric ? kg : kg * Self.poundsPerKilogram
    }

    /// Centimetres or inches.
    public func length(cm: Double) -> Double {
        self == .metric ? cm : cm / Self.centimetresPerInch
    }

    public func temperature(celsius: Double) -> Double {
        self == .metric ? celsius : celsius * 9 / 5 + 32
    }

    public func temperatureDifference(celsius: Double) -> Double {
        self == .metric ? celsius : celsius * 9 / 5
    }

    /// Whole inches, split into feet and inches.
    public static func feetAndInches(cm: Double) -> (feet: Int, inches: Int) {
        let total = Int((cm / centimetresPerInch).rounded())
        return (total / 12, total % 12)
    }
}
