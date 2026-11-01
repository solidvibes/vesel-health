import Foundation
import Observation
import VeselCore
import VeselStorage

@MainActor
@Observable
final class AboutYouModel {
    /// Nil until read.
    private(set) var profile: Profile?
    var editingProfile: Bool
    private(set) var savingProfile = false
    /// The last save didn't reach the band, so nothing was stored.
    private(set) var profileNotSaved = false

    private let database: AppDatabase
    private let clock: any VeselClock
    private let unitsStore: UnitsStore
    private let writeProfile: (Profile) async -> Bool

    /// `writeProfile` writes to the Loop, then the phone; true once both have it.
    init(database: AppDatabase, clock: any VeselClock, units: UnitsStore, opensEditor: Bool, writeProfile: @escaping (Profile) async -> Bool) {
        self.database = database
        self.clock = clock
        unitsStore = units
        self.writeProfile = writeProfile
        editingProfile = opensEditor
    }

    var currentYear: Int { Calendar.current.component(.year, from: clock.now) }

    var units: Units { unitsStore.units }

    func load() async {
        profile = try? await database.profile()
    }

    /// Only how the screens write weight, height, waist and skin temperature: never sent to the Loop.
    func setUnits(_ units: Units) async {
        try? await database.setUnits(units)
    }

    func editProfile() {
        profileNotSaved = false
        editingProfile = true
    }

    /// Band first, then the phone. True once both have it; false at once while another save runs. A change to only waist or
    /// another device's VO2max goes straight to the phone: the Loop doesn't keep them.
    func saveProfile(_ changed: Profile) async -> Bool {
        guard !savingProfile else { return false }
        savingProfile = true
        profileNotSaved = false
        let saved: Bool
        if let profile, changed.sameOnBand(as: profile) {
            saved = (try? await database.save(changed)) != nil
        } else {
            saved = await writeProfile(changed)
        }
        savingProfile = false
        if saved {
            profile = changed
        } else {
            profileNotSaved = true
        }
        return saved
    }
}
