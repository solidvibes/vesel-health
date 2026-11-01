import VeselCore

extension DayKey {
    /// A day read back from a stored row.
    init(stored text: String) throws {
        guard let day = DayKey(text) else { throw StorageError.badDay }
        self = day
    }
}
