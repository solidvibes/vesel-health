import Testing
import VeselCore

struct ProfileDraftTests {
    let stored = Profile(birthYear: 1990, sex: .male, heightCm: 180.0, weightKg: 75.0, sleepGoalMinutes: 450)

    @Test func aStoredProfileFillsWholeNumbersAndComesBackTheSame() {
        let draft = ProfileDraft(profile: stored)
        #expect(draft.birthYear == "1990")
        #expect(draft.height == "180")
        #expect(draft.weight == "75")
        #expect(draft.sex == .male)
        #expect(draft.sleepGoalHours == 7.5)
        #expect(draft.birthYearError(currentYear: 2026) == nil)
        #expect(draft.heightError == nil)
        #expect(draft.weightError == nil)
        #expect(draft.profile(currentYear: 2026) == stored)
    }

    @Test func emptyFieldsShowNoErrorButGiveNoProfile() {
        let draft = ProfileDraft()
        #expect(draft.birthYearError(currentYear: 2026) == nil)
        #expect(draft.heightError == nil)
        #expect(draft.weightError == nil)
        #expect(draft.profile(currentYear: 2026) == nil)
    }

    @Test func outOfRangeOrNotANumberIsAnError() {
        var draft = ProfileDraft(profile: stored)
        draft.birthYear = "2011"
        #expect(draft.birthYearError(currentYear: 2026) == "Enter a year between 1920 and 2010")
        draft.birthYear = "19x0"
        #expect(draft.birthYearError(currentYear: 2026) == "Enter a year like 1990")
        draft.height = "119"
        #expect(draft.heightError == "Enter a height between 120 and 230 cm")
        draft.weight = "75.5"
        #expect(draft.weightError == "Enter your weight in kilograms")
        #expect(draft.profile(currentYear: 2026) == nil)
    }

    @Test func noSexGivesNoProfile() {
        var draft = ProfileDraft(profile: stored)
        draft.sex = nil
        #expect(draft.profile(currentYear: 2026) == nil)
    }

    @Test func aChangeGivesTheChangedProfile() {
        var draft = ProfileDraft(profile: stored)
        draft.weight = "78"
        draft.sleepGoalHours = 8
        #expect(draft.profile(currentYear: 2026) == Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 78, sleepGoalMinutes: 480))
    }

    @Test func waistAndOutsideVO2maxAreOptionalAndChecked() {
        var draft = ProfileDraft(profile: stored)
        #expect(draft.waist == "")
        #expect(draft.measuredVO2max == "")
        #expect(draft.waistError == nil)
        #expect(draft.measuredVO2maxError == nil)
        #expect(draft.profile(currentYear: 2026)?.waistCm == nil)

        draft.waist = "49"
        #expect(draft.waistError == "Enter a waist between 50 and 200 cm")
        #expect(draft.profile(currentYear: 2026) == nil)
        draft.waist = "201"
        #expect(draft.waistError == "Enter a waist between 50 and 200 cm")
        draft.waist = "8x"
        #expect(draft.waistError == "Enter your waist in centimetres")
        draft.waist = "84"
        #expect(draft.waistError == nil)

        draft.measuredVO2max = "9"
        #expect(draft.measuredVO2maxError == "Enter a VO2max between 10 and 90")
        draft.measuredVO2max = "91"
        #expect(draft.measuredVO2maxError == "Enter a VO2max between 10 and 90")
        draft.measuredVO2max = "45.5"
        #expect(draft.measuredVO2maxError == "Enter a whole number like 45")
        draft.measuredVO2max = "46"
        #expect(draft.measuredVO2maxError == nil)

        let withBoth = draft.profile(currentYear: 2026)
        #expect(withBoth?.waistCm == 84)
        #expect(withBoth?.measuredVO2max == 46)
        #expect(ProfileDraft(profile: withBoth!).waist == "84")
        #expect(ProfileDraft(profile: withBoth!).measuredVO2max == "46")

        draft.waist = ""
        draft.measuredVO2max = ""
        #expect(draft.profile(currentYear: 2026) == stored)
    }

    @Test func onlyTheLoopsFieldsCountForTheBand() {
        var changed = stored
        changed.waistCm = 84
        changed.measuredVO2max = 46
        #expect(changed.sameOnBand(as: stored))
        changed.weightKg = 76
        #expect(!changed.sameOnBand(as: stored))
    }

    // MARK: Units

    let withWaist = Profile(birthYear: 1990, sex: .male, heightCm: 180.0, weightKg: 75.0, sleepGoalMinutes: 450, waistCm: 84)

    @Test func inUSAStoredProfileShowsInPoundsFeetAndInches() {
        let draft = ProfileDraft(profile: withWaist, units: .us)
        #expect(draft.weight == "165")
        #expect(draft.heightFeet == "5")
        #expect(draft.heightInches == "11")
        #expect(draft.waist == "33")
        #expect(draft.heightError == nil)
        #expect(draft.weightError == nil)
        #expect(draft.waistError == nil)
    }

    @Test func nothingTypedGivesBackTheStoredProfileExactly() {
        // 165 lb would be 74.84 kg and 5 ft 11 in 180.34 cm: an untouched field keeps the stored number instead.
        #expect(ProfileDraft(profile: withWaist, units: .us).profile(currentYear: 2026) == withWaist)
        let odd = Profile(birthYear: 1990, sex: .female, heightCm: 167.4, weightKg: 61.3, sleepGoalMinutes: 480, waistCm: 71.6)
        #expect(ProfileDraft(profile: odd, units: .metric).profile(currentYear: 2026) == odd)
        #expect(ProfileDraft(profile: odd, units: .us).profile(currentYear: 2026) == odd)
    }

    @Test func switchingUnitsNeverChangesWhatGoesToTheLoop() throws {
        var draft = ProfileDraft(profile: withWaist, units: .metric)
        draft.switchUnits(to: .us)
        #expect(draft.weight == "165")
        let inUS = try #require(draft.profile(currentYear: 2026))
        #expect(inUS == withWaist)
        #expect(inUS.sameOnBand(as: withWaist))
        draft.switchUnits(to: .metric)
        #expect(draft.weight == "75")
        let back = try #require(draft.profile(currentYear: 2026))
        #expect(back == withWaist)
        #expect(back.sameOnBand(as: withWaist))

        var fromUS = ProfileDraft(profile: withWaist, units: .us)
        fromUS.switchUnits(to: .metric)
        #expect(fromUS.profile(currentYear: 2026) == withWaist)
    }

    @Test func typedUSValuesConvertWithoutRounding() throws {
        var draft = ProfileDraft(profile: stored, units: .us)
        draft.weight = "170"
        draft.heightFeet = "6"
        draft.heightInches = "0"
        let profile = try #require(draft.profile(currentYear: 2026))
        // 170 ÷ 2.20462 = 77.1108 kg; 72 in × 2.54 = 182.88 cm.
        #expect(abs(profile.weightKg - 77.1108) < 1e-3)
        #expect(abs(profile.heightCm - 182.88) < 1e-9)
        draft.waist = "33"
        // 33 × 2.54 = 83.82 cm.
        #expect(abs((draft.profile(currentYear: 2026)?.waistCm ?? 0) - 83.82) < 1e-9)
    }

    @Test func usEdgesAreCheckedAgainstTheMetricRanges() {
        var draft = ProfileDraft(profile: withWaist, units: .us)
        draft.weight = "600"
        #expect(draft.weightError == "Enter a weight between 67 and 551 lb")
        draft.weight = "16x"
        #expect(draft.weightError == "Enter your weight in pounds")

        func height(_ feet: Int, _ inches: Int) -> String? {
            var draft = ProfileDraft(profile: withWaist, units: .us)
            draft.heightFeet = String(feet)
            draft.heightInches = String(inches)
            return draft.heightError
        }
        // 4 ft 0 in = 121.92 cm, 7 ft 6 in = 228.6 cm; 3 ft 11 in = 119.38 cm, 7 ft 7 in = 231.14 cm.
        #expect(height(4, 0) == nil)
        #expect(height(7, 6) == nil)
        #expect(height(3, 11) == "Enter a height between 4 ft 0 in and 7 ft 6 in")
        #expect(height(7, 7) == "Enter a height between 4 ft 0 in and 7 ft 6 in")

        func weight(_ pounds: Int) -> String? {
            var draft = ProfileDraft(profile: withWaist, units: .us)
            draft.weight = String(pounds)
            return draft.weightError
        }
        // 67 lb = 30.39 kg, 551 lb = 249.93 kg; 66 lb = 29.94 kg, 552 lb = 250.38 kg.
        #expect(weight(67) == nil)
        #expect(weight(551) == nil)
        #expect(weight(66) != nil)
        #expect(weight(552) != nil)

        func waist(_ inches: Int) -> String? {
            var draft = ProfileDraft(profile: withWaist, units: .us)
            draft.waist = String(inches)
            return draft.waistError
        }
        // 20 in = 50.8 cm, 78 in = 198.12 cm; 19 in = 48.26 cm, 79 in = 200.66 cm.
        #expect(waist(20) == nil)
        #expect(waist(78) == nil)
        #expect(waist(19) == "Enter a waist between 20 and 78 in")
        #expect(waist(79) == "Enter a waist between 20 and 78 in")
    }

    @Test func aValidUSEdgeStaysValidInMetric() {
        for (feet, inches, pounds, waist) in [(4, 0, 67, 20), (7, 6, 551, 78)] {
            var draft = ProfileDraft(profile: withWaist, units: .us)
            draft.heightFeet = String(feet)
            draft.heightInches = String(inches)
            draft.weight = String(pounds)
            draft.waist = String(waist)
            #expect(draft.profile(currentYear: 2026) != nil)
            let inUS = draft.profile(currentYear: 2026)
            draft.switchUnits(to: .metric)
            #expect(draft.heightError == nil)
            #expect(draft.weightError == nil)
            #expect(draft.waistError == nil)
            #expect(draft.profile(currentYear: 2026) == inUS)
        }
    }

    @Test func unchangedFieldsKeepTheirExactStoredValueThroughSwitchesAndOtherEdits() throws {
        let odd = Profile(birthYear: 1990, sex: .female, heightCm: 167.4, weightKg: 61.3, sleepGoalMinutes: 480, waistCm: 71.6)
        var draft = ProfileDraft(profile: odd, units: .metric)
        draft.switchUnits(to: .us)
        #expect(draft.profile(currentYear: 2026) == odd)
        draft.switchUnits(to: .metric)
        #expect(draft.profile(currentYear: 2026) == odd)

        draft.switchUnits(to: .us)
        draft.weight = "140"
        let edited = try #require(draft.profile(currentYear: 2026))
        #expect(abs(edited.weightKg - 140 / 2.20462) < 1e-9)
        #expect(edited.heightCm == 167.4)
        #expect(edited.waistCm == 71.6)
    }

    @Test func switchingAfterAnEditCarriesTheEditedValueAndClearsANonNumber() throws {
        var draft = ProfileDraft(profile: withWaist, units: .us)
        draft.weight = "170"
        draft.waist = "3x"
        draft.switchUnits(to: .metric)
        #expect(draft.weight == "77")
        #expect(draft.waist == "")
        let profile = try #require(draft.profile(currentYear: 2026))
        #expect(abs(profile.weightKg - 170 / 2.20462) < 1e-9)
        #expect(profile.heightCm == 180)
        #expect(profile.waistCm == nil)
    }
}
