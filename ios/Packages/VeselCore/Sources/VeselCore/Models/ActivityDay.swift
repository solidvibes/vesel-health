public struct ActivityDay: Sendable, Equatable {
    public var day: DayKey
    public var steps: Int
    public var activeSeconds: Int
    public var calories: Calories

    public struct Calories: Sendable, Equatable, Codable {
        public var bmr: Int
        public var activity: Int
        public var total: Int

        public init(bmr: Int, activity: Int, total: Int) {
            self.bmr = bmr
            self.activity = activity
            self.total = total
        }
    }

    public init(day: DayKey, steps: Int, activeSeconds: Int, calories: Calories) {
        self.day = day
        self.steps = steps
        self.activeSeconds = activeSeconds
        self.calories = calories
    }
}
