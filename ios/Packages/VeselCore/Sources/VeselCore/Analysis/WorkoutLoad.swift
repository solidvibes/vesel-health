import Foundation

/// Polar's own words for its cardio load rating (1–5), only those confirmed on the owner's Loop. Vesel makes no word of its own.
public enum PolarLoadWord {
    /// Empty until the owner checks a rating against Polar's own app (the SDK's comment expects very low, low, medium, high,
    /// very high).
    public static let confirmed: [Int: String] = [:]
}

/// One workout's load: Polar's cardio load, or its older training load when there is none. Never added up over days.
public struct WorkoutLoad: Sendable, Equatable {
    public enum Source: String, Sendable {
        case cardioLoad, trainingLoad
    }

    public static let method = "workout"
    public static let version = 1

    public var number: Double
    public var source: Source
    /// Polar's word for its rating, once confirmed; only beside a cardio load.
    public var polarWord: String?

    /// Nil when the Loop gave neither load.
    public static func make(_ workout: Workout) -> WorkoutLoad? {
        if let cardioLoad = workout.cardioLoad {
            return WorkoutLoad(number: cardioLoad, source: .cardioLoad, polarWord: workout.cardioLoadRating.flatMap { PolarLoadWord.confirmed[$0] })
        }
        return workout.trainingLoad.map { WorkoutLoad(number: $0, source: .trainingLoad, polarWord: nil) }
    }

    /// The Workout page's row: "Cardio load 172", with Polar's word once confirmed ("Cardio load 172 · High"), or "Training load 140".
    public var text: String {
        switch source {
        case .cardioLoad: (["Cardio load \(numberText)"] + [polarWord].compactMap { $0 }).joined(separator: " · ")
        case .trainingLoad: "Training load \(numberText)"
        }
    }

    /// In a line or on a card: "load 172", or "training load 140" when that is all the Loop gave.
    public var shortText: String { source == .cardioLoad ? "load \(numberText)" : "training load \(numberText)" }

    /// For VoiceOver: "cardio load 172", "training load 140".
    public var spokenText: String { source == .cardioLoad ? "cardio load \(numberText)" : "training load \(numberText)" }

    private var numberText: String { NumberText.decimal(number, 0) }

    /// Where the load, Polar's rating and the sport came from.
    public static func explanation(_ workout: Workout, label: WorkoutLabel, route: WorkoutRouteSummary?) -> Explanation {
        var inputs: [Explanation.Input] = []
        var sentences: [String] = []
        switch make(workout) {
        case let load? where load.source == .cardioLoad:
            inputs.append(.init(name: "cardioLoad", value: load.number, unit: "load"))
            sentences.append(
                "Cardio load \(NumberText.decimal(load.number, 0)) is Polar's own number for this workout, from your heart rate and its length, as the Loop gave it.")
        case let load?:
            inputs.append(.init(name: "trainingLoad", value: load.number, unit: "load"))
            sentences.append(
                "The Loop gave no cardio load, so this is its older training load, \(NumberText.decimal(load.number, 0)), as the Loop gave it.")
        case nil:
            sentences.append("The Loop gave no load for this workout.")
        }
        if let rating = workout.cardioLoadRating {
            inputs.append(.init(name: "cardioLoadRating", value: Double(rating), unit: "of 5"))
            sentences.append("Polar rated it \(rating) of 5, comparing it with your last 90 days.")
        }
        if let route {
            inputs.append(.init(name: "routeCoverage", value: route.coverage, unit: "share"))
        }
        sentences.append(sportSentence(label, route: route))
        return Explanation(method: method, version: version, inputs: inputs, text: sentences.joined(separator: " "))
    }

    private static func sportSentence(_ label: WorkoutLabel, route: WorkoutRouteSummary?) -> String {
        switch label.source {
        case .owner: return "You chose the sport."
        case .band: return "The Loop gave the sport."
        case .speed:
            let speed = NumberText.decimal(route?.averageSpeedKmh ?? 0, 1)
            let covered = NumberText.decimal((route?.coverage ?? 0) * 100, 0)
            return
                "The sport is guessed from speed: \(speed) km/h over a route covering \(covered) % of the workout (over \(NumberText.decimal(WorkoutThresholds.guessSpeedKmh, 0)) km/h is cycling, else running)."
        case .timeOfDay:
            return
                "The sport is guessed from time of day: the one you did most often within \(NumberText.decimal(WorkoutThresholds.guessWindowHours, 0)) hours of this time over the \(WorkoutThresholds.guessHistoryDays) days before."
        case .none: return "The Loop gave no sport, and nothing was close enough to guess one."
        }
    }
}
