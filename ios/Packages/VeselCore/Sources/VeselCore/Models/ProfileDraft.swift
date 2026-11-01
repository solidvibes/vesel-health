/// The About you form as typed: the same fields and checks in pairing and in Loop & settings.
/// Every check runs on the metric value against the metric range, whatever the units.
public struct ProfileDraft: Equatable, Sendable {
    public private(set) var units: Units
    public var birthYear = ""
    /// Centimetres; unused in US.
    public var height = ""
    /// US only.
    public var heightFeet = ""
    /// US only.
    public var heightInches = ""
    /// Kilograms, or pounds in US.
    public var weight = ""
    public var sex: Sex?
    public var sleepGoalHours = 8.0
    /// Optional: blank means none. Centimetres, or inches in US.
    public var waist = ""
    /// Optional: blank means none.
    public var measuredVO2max = ""

    /// The metric value each length and weight field was filled from, and the text it was filled with. A field whose
    /// text is still that text gives back exactly that value, so showing it in other units never changes the profile.
    private var filled = Filled()

    private struct Filled: Equatable, Sendable {
        var heightCm: Double?
        var height = ""
        var heightFeet = ""
        var heightInches = ""
        var weightKg: Double?
        var weight = ""
        var waistCm: Double?
        var waist = ""
    }

    public init(units: Units = .metric) {
        self.units = units
    }

    /// Height, weight and waist are stored as `Double` but typed as whole numbers.
    public init(profile: Profile, units: Units = .metric) {
        self.units = units
        birthYear = String(profile.birthYear)
        sex = profile.sex
        sleepGoalHours = Double(profile.sleepGoalMinutes) / 60
        measuredVO2max = profile.measuredVO2max.map { String(Int($0.rounded())) } ?? ""
        fill(heightCm: profile.heightCm, weightKg: profile.weightKg, waistCm: profile.waistCm)
    }

    /// Shows the fields in `new` units; each keeps the metric value it stood for.
    public mutating func switchUnits(to new: Units) {
        guard new != units else { return }
        let values = (heightCm, weightKg, waistCm)
        units = new
        fill(heightCm: values.0, weightKg: values.1, waistCm: values.2)
    }

    private mutating func fill(heightCm: Double?, weightKg: Double?, waistCm: Double?) {
        func whole(_ value: Double) -> String { String(Int(value.rounded())) }
        height = ""
        heightFeet = ""
        heightInches = ""
        if let heightCm {
            if units == .metric {
                height = whole(heightCm)
            } else {
                let split = Units.feetAndInches(cm: heightCm)
                heightFeet = String(split.feet)
                heightInches = String(split.inches)
            }
        }
        weight = weightKg.map { whole(units.weight(kg: $0)) } ?? ""
        waist = waistCm.map { whole(units.length(cm: $0)) } ?? ""
        filled = Filled(
            heightCm: heightCm, height: height, heightFeet: heightFeet, heightInches: heightInches,
            weightKg: weightKg, weight: weight, waistCm: waistCm, waist: waist
        )
    }

    /// Nil when empty or not a whole number.
    public var heightCm: Double? {
        if units == .metric {
            return height == filled.height ? filled.heightCm : Int(height).map(Double.init)
        }
        if heightFeet == filled.heightFeet && heightInches == filled.heightInches { return filled.heightCm }
        guard let feet = Int(heightFeet), let inches = heightInches.isEmpty ? 0 : Int(heightInches) else { return nil }
        return Double(feet * 12 + inches) * Units.centimetresPerInch
    }

    /// Nil when empty or not a whole number.
    public var weightKg: Double? {
        if weight == filled.weight { return filled.weightKg }
        return Int(weight).map { units == .metric ? Double($0) : Double($0) / Units.poundsPerKilogram }
    }

    /// Nil when empty or not a whole number.
    public var waistCm: Double? {
        if waist == filled.waist { return filled.waistCm }
        return Int(waist).map { units == .metric ? Double($0) : Double($0) * Units.centimetresPerInch }
    }

    public func birthYearError(currentYear: Int) -> String? {
        guard let year = Int(birthYear) else { return birthYear.isEmpty ? nil : "Enter a year like 1990" }
        return (1920...(currentYear - 16)).contains(year) ? nil : "Enter a year between 1920 and \(currentYear - 16)"
    }

    /// US bounds are the whole feet and inches inside 120–230 cm.
    public var heightError: String? {
        let metric = units == .metric
        guard let heightCm else {
            let empty = metric ? height.isEmpty : heightFeet.isEmpty && heightInches.isEmpty
            return empty ? nil : (metric ? "Enter your height in centimetres" : "Enter your height in feet and inches")
        }
        guard !(120.0...230.0).contains(heightCm) else { return nil }
        return metric ? "Enter a height between 120 and 230 cm" : "Enter a height between 4 ft 0 in and 7 ft 6 in"
    }

    /// US bounds are the whole pounds inside 30–250 kg.
    public var weightError: String? {
        let metric = units == .metric
        guard let weightKg else { return weight.isEmpty ? nil : (metric ? "Enter your weight in kilograms" : "Enter your weight in pounds") }
        guard !(30.0...250.0).contains(weightKg) else { return nil }
        return metric ? "Enter a weight between 30 and 250 kg" : "Enter a weight between 67 and 551 lb"
    }

    /// US bounds are the whole inches inside 50–200 cm.
    public var waistError: String? {
        let metric = units == .metric
        guard let waistCm else { return waist.isEmpty ? nil : (metric ? "Enter your waist in centimetres" : "Enter your waist in inches") }
        guard !(50.0...200.0).contains(waistCm) else { return nil }
        return metric ? "Enter a waist between 50 and 200 cm" : "Enter a waist between 20 and 78 in"
    }

    public var measuredVO2maxError: String? {
        guard let value = Int(measuredVO2max) else { return measuredVO2max.isEmpty ? nil : "Enter a whole number like 45" }
        return (10...90).contains(value) ? nil : "Enter a VO2max between 10 and 90"
    }

    /// Nil while a required field is empty or any field has an error.
    public func profile(currentYear: Int) -> Profile? {
        guard let sex, let year = Int(birthYear), let heightCm, let weightKg,
            birthYearError(currentYear: currentYear) == nil, heightError == nil, weightError == nil,
            waistError == nil, measuredVO2maxError == nil
        else { return nil }
        return Profile(
            birthYear: year, sex: sex, heightCm: heightCm, weightKg: weightKg, sleepGoalMinutes: Int(sleepGoalHours * 60),
            waistCm: waistCm, measuredVO2max: Int(measuredVO2max).map(Double.init)
        )
    }
}
