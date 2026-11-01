import Foundation

/// A word the screens can explain. The raw value is the launch flag (`-VeselMeaning remSleep`) and the term link's address.
public enum Term: String, CaseIterable, Sendable, Hashable {
    case deepSleep, lightSleep, remSleep, awake, sleepTime
    case hrv, restingHeartRate, lowestHeartRate, breathing, skinTemperature
    case recovery, usualRange, stress, highStress, heartRate, howTheBandKnows
    case heartFitness, vo2max, steps
}

/// What one term means, in reading order. Written once, here; screens add only their own number for the day shown.
public struct Meaning: Sendable, Equatable {
    public struct Section: Sendable, Equatable {
        public var heading: String
        public var text: String

        public init(_ heading: String, _ text: String) {
            self.heading = heading
            self.text = text
        }
    }

    public var term: Term
    public var title: String
    public var sections: [Section]
    /// "How the band knows": shown after the screen's own number.
    public var howTheBandKnows: String?
    /// A worked-out line that belongs to the term itself, shown folded after the screen's explanations.
    public var workedOut: String?
}

public enum Glossary {
    public struct Group: Sendable, Equatable {
        public var title: String
        public var terms: [Term]
    }

    /// The list in Loop & settings: every term in exactly one group.
    public static let groups: [Group] = [
        Group(title: "Sleep", terms: [.deepSleep, .lightSleep, .remSleep, .awake, .sleepTime]),
        Group(title: "Recovery", terms: [.recovery, .hrv, .breathing, .skinTemperature]),
        Group(title: "Heart", terms: [.heartRate, .restingHeartRate, .lowestHeartRate, .heartFitness, .vo2max]),
        Group(title: "Stress", terms: [.stress, .highStress]),
        Group(title: "Movement", terms: [.steps]),
        Group(title: "About the readings", terms: [.usualRange, .howTheBandKnows]),
    ]

    public static func meaning(_ term: Term) -> Meaning {
        switch term {
        case .deepSleep: deepSleep
        case .lightSleep: lightSleep
        case .remSleep: remSleep
        case .awake: awake
        case .sleepTime: sleepTime
        case .hrv: hrv
        case .restingHeartRate: restingHeartRate
        case .lowestHeartRate: lowestHeartRate
        case .breathing: breathing
        case .skinTemperature: skinTemperature
        case .recovery: recovery
        case .usualRange: usualRange
        case .stress: stress
        case .highStress: highStress
        case .heartRate: heartRate
        case .howTheBandKnows: howTheBandKnows
        case .heartFitness: heartFitness
        case .vo2max: vo2max
        case .steps: steps
        }
    }

    private static let shareOfAsleep = "The share is the stage's minutes ÷ your time asleep, rounded."
    private static let shareOfInBed = "The share is the stage's minutes ÷ your time in bed, rounded."

    private static let deepSleep = Meaning(
        term: .deepSleep, title: "Deep sleep",
        sections: [
            .init("What it is", "The deepest, slowest stage of sleep. Your breathing and heart slow down, your muscles relax, and you are hardest to wake."),
            .init("Good or bad", "Good. It is the part of sleep most linked with waking up physically rested."),
            .init(
                "A lot or a little",
                "More usually means your body got the rest it needed. One night with little says not much on its own; a run of them is worth noticing."),
            .init(
                "What's normal",
                "Often 1 to 2 hours a night, about 15 to 25 % of sleep in younger adults and slowly less with age. Most of it comes in the first half of the night."
            ),
            .init(
                "What affects it",
                "A late heavy meal, a warm bedroom, illness and irregular bedtimes tend to cut it. Alcohol can deepen the first hours, then makes the rest of the night lighter and more broken. An active day and catching up after a short night tend to add to it."
            ),
        ],
        howTheBandKnows:
            "The Loop can't see brain waves. Polar estimates the stage from how still you are and how your heart beats: in deep sleep you barely move and your heartbeat is slow and steady.",
        workedOut: shareOfAsleep
    )

    private static let lightSleep = Meaning(
        term: .lightSleep, title: "Light sleep",
        sections: [
            .init("What it is", "The in-between stage. You drift in and out of it all night, between waking, deep sleep and REM."),
            .init("Good or bad", "Neither. It's needed, not wasted time."),
            .init(
                "A lot or a little",
                "It's normally the biggest share of the night. A lot of light sleep isn't a problem by itself; it only matters if it crowds out deep sleep and REM night after night."
            ),
            .init("What's normal", "About half of your sleep, often more."),
            .init("What affects it", "Broken sleep raises its share: noise, light, heat, caffeine, alcohol, stress."),
        ],
        howTheBandKnows: "Estimated by Polar from movement and heart rhythm, like every stage.",
        workedOut: shareOfAsleep
    )

    private static let remSleep = Meaning(
        term: .remSleep, title: "REM sleep",
        sections: [
            .init("What it is", "The dreaming stage. Your brain is nearly as busy as when you're awake, while your body stays still."),
            .init("Good or bad", "Good. It helps you sort memories, learn and settle emotions."),
            .init(
                "A lot or a little",
                "REM comes in longer stretches towards morning, so a short night or an early alarm cuts it first. Alcohol pushes it back too."),
            .init("What's normal", "About a fifth to a quarter of sleep, often 1½ to 2 hours in a full night, in cycles roughly every 90 minutes."),
            .init("What affects it", "Short sleep, early alarms, alcohol and some medicines lower it."),
        ],
        howTheBandKnows: "Estimated by Polar from movement and heart rhythm: in REM you're still, but your heart rate is less even than in deep sleep.",
        workedOut: shareOfAsleep
    )

    private static let awake = Meaning(
        term: .awake, title: "Awake",
        sections: [
            .init("What it is", "Short wakings between falling asleep and getting up. You won't remember most of them."),
            .init("Good or bad", "Some is normal. Everyone wakes briefly several times a night."),
            .init("A lot or a little", "More than usual often means lighter, broken sleep: noise, heat, a late drink, worry or needing the toilet."),
            .init("What's normal", "Up to about half an hour in a night is common, and it grows a little with age."),
            .init("What affects it", "Room temperature, noise, light, alcohol, caffeine, late meals, stress."),
        ],
        howTheBandKnows: "Estimated by Polar from movement and heart rate rising.",
        workedOut: shareOfInBed
    )

    private static let sleepTime = Meaning(
        term: .sleepTime, title: "Sleep time",
        sections: [
            .init("What it is", "How long you were actually asleep: from falling asleep to getting up, minus the wakings."),
            .init("Good or bad", "Enough sleep is one of the best-supported things for health, mood and recovery."),
            .init(
                "A lot or a little",
                "A short night now and then is fine. Regularly less than you need adds up. Much longer than usual can mean catching up, or that you're coming down with something."
            ),
            .init("What's normal", "Most adults need 7 to 9 hours. Your Sleep line compares you with your own normal, not with that number."),
            .init("What affects it", "Bedtime, alarms, caffeine late in the day, alcohol, light and screens, stress, illness."),
        ],
        howTheBandKnows: "Polar sees you fall asleep and wake from movement and heart rate.",
        workedOut: nil
    )

    private static let hrv = Meaning(
        term: .hrv, title: "HRV",
        sections: [
            .init(
                "What it is",
                "Heart rate variability: how much the time between heartbeats changes from beat to beat. A rested heart doesn't tick like a metronome; small changes show the calming side of your nervous system is more active."
            ),
            .init("Good or bad", "Higher than your usual is generally good."),
            .init(
                "A lot or a little",
                "Above your usual usually means you're well rested. Clearly below often follows alcohol, a late meal, a short night, a hard day, stress or the start of a cold."
            ),
            .init(
                "What's normal",
                "Very personal. Anything from about 20 to over 100 ms can be normal, and it falls with age. Compare it only with your own usual, never with someone else's."
            ),
            .init("What affects it", "Alcohol (strongly), sleep, illness, hard exercise, stress, not drinking enough water, late meals."),
        ],
        howTheBandKnows:
            "The Loop times each beat from your pulse while you sleep. Polar's Nightly Recharge turns the beat-to-beat changes of the first hours of sleep into one number (RMSSD, a standard measure).",
        workedOut: nil
    )

    private static let restingHeartRate = Meaning(
        term: .restingHeartRate, title: "Resting heart rate",
        sections: [
            .init(
                "What it is",
                "How fast your heart beats when you're fully at rest. Here: its average in the first hours of sleep, from Polar's Nightly Recharge."),
            .init("Good or bad", "Lower than your usual usually means more rested."),
            .init(
                "A lot or a little",
                "A few beats above your usual often follows alcohol, a late meal, a hot night, hard exercise, stress or an illness on its way. Over months, a lower resting heart rate generally goes with better fitness."
            ),
            .init(
                "What's normal",
                "Awake at rest, 60 to 100 bpm counts as normal for adults. Asleep it's lower, often in the 50s, and fit people can be in the 40s."),
            .init("What affects it", "Alcohol, late meals, heat, illness, fitness, caffeine, some medicines."),
        ],
        howTheBandKnows:
            "From the Loop's beat timing in the first hours of sleep; Polar's Nightly Recharge gives the average time between beats, and Vesel turns it into beats per minute.",
        workedOut: nil
    )

    private static let lowestHeartRate = Meaning(
        term: .lowestHeartRate, title: "Lowest heart rate",
        sections: [
            .init("What it is", "The slowest your heart went during the night: the lowest 5-minute reading while you slept."),
            .init("Good or bad", "Lower than your usual is usually a sign of a restful night."),
            .init("A lot or a little", "Higher than usual has the same causes as a higher resting heart rate: alcohol, a late meal, heat, stress, illness."),
            .init("What's normal", "Often in the 40s or 50s for adults; it's personal."),
            .init("What affects it", "The same things as resting heart rate."),
        ],
        howTheBandKnows: "The Loop records your heart rate every 5 minutes, day and night; Vesel takes the lowest one between falling asleep and waking.",
        workedOut: nil
    )

    private static let breathing = Meaning(
        term: .breathing, title: "Breathing",
        sections: [
            .init("What it is", "How many breaths you take a minute while asleep."),
            .init("Good or bad", "Neither. What matters is that it stays steady."),
            .init(
                "A lot or a little",
                "For most people it barely changes night to night, so a clear rise above your usual is worth a look. It can come with a cold or fever, a hot room or alcohol. It is not a diagnosis."
            ),
            .init("What's normal", "About 12 to 20 breaths a minute at rest for adults, often at the low end asleep."),
            .init("What affects it", "Illness, temperature, alcohol, sleeping position."),
        ],
        howTheBandKnows:
            "Breathing gently changes your heart rhythm: it speeds up a little as you breathe in and slows as you breathe out. Polar reads your breathing from that.",
        workedOut: nil
    )

    private static let skinTemperature = Meaning(
        term: .skinTemperature, title: "Skin temperature",
        sections: [
            .init("What it is", "The temperature of the skin under the Loop. It is not your body's core temperature."),
            .init("Good or bad", "Neither. The change from your usual night is what counts."),
            .init(
                "A lot or a little",
                "A night clearly warmer than usual can come with illness, alcohol, a warm room or heavy bedding, and for women with the monthly cycle. Cooler often just means a cold room or an arm outside the covers."
            ),
            .init(
                "What's normal",
                "Skin is warmer asleep and cooler when you're up and about; daytime swings of a few degrees are normal (weather, clothes, exercise). At night, most people stay within a few tenths of a degree of their usual."
            ),
            .init("What affects it", "Room temperature, bedding, alcohol, illness, the menstrual cycle, how tight the band sits."),
        ],
        howTheBandKnows: "A sensor on the inside of the Loop, every 5 minutes.",
        workedOut: nil
    )

    private static let recovery = Meaning(
        term: .recovery, title: "Recovery (Polar's Nightly Recharge)",
        sections: [
            .init(
                "What it is",
                "Polar's morning verdict on how well your body recovered overnight, from very poor to very good (1 to 6). It looks at your heart rate, HRV and breathing early in the night and at your sleep, each against your own usual."
            ),
            .init("Good or bad", "OK or better means you're about where you usually are or better. Compromised or lower means less recovered than usual."),
            .init("A lot or a little", "A low morning now and then is normal: take it as a hint to go easier that day, not a warning."),
            .init("What's normal", "Most mornings land around OK or good, because Polar compares you with yourself."),
            .init("What affects it", "Everything that affects sleep, HRV and resting heart rate: alcohol, late meals, stress, hard exercise, illness."),
        ],
        howTheBandKnows: "Polar works it out from the Loop's overnight readings. Vesel shows Polar's verdict as it is and doesn't change it.",
        workedOut: nil
    )

    private static let usualRange = Meaning(
        term: .usualRange, title: "Usual range",
        sections: [
            .init(
                "What it is",
                "Your own normal for a measure: the middle band of your last 28 nights (your average, plus and minus one standard deviation). About two in three of your nights fall inside it."
            ),
            .init(
                "Good or bad",
                "Inside means you were like you usually are. Outside isn't bad by itself: about one night in three lands outside. The recovery card colours it so you can see which side it fell on; alerts only come when something stays clearly away from your usual."
            ),
            .init("What's normal", "It needs 7 nights before it shows: \"\(LearningText.nights(0))\"."),
            .init("What affects it", "It follows your last 28 nights, so it moves slowly as your life changes."),
            .init("Why your own", "People differ a lot. Comparing you with yourself is fairer than comparing you with an average person."),
        ],
        howTheBandKnows: nil,
        workedOut:
            "The mean ± 1 standard deviation of the previous \(PersonalRange.windowNights) nights, not counting the night itself, from \(PersonalRange.minimumNights) nights on (method \(PersonalRange.method), version \(PersonalRange.version))."
    )

    private static let stress = Meaning(
        term: .stress, title: "Stress",
        sections: [
            .init(
                "What it is",
                "How strained your body is during the day, from 0 to 100, worked out by Vesel between 06:00 and 22:00. It's your body's response, not your mood: excitement and worry can look alike. Exercise is left out."
            ),
            .init("Good or bad", "Some is normal and healthy: it's how your body rises to a task."),
            .init("A lot or a little", "What's worth noticing is long stretches of high with no calm in between."),
            .init("What's normal", "Calm most of the day with short peaks. Calm is under 34, moderate 34 to 66, high 67 and up."),
            .init("What affects it", "Pressure and worry, caffeine, a short night, illness, the day after alcohol, heat, being on your feet a lot."),
        ],
        howTheBandKnows:
            "The Loop records short stretches of your beat-to-beat timing through the day. Vesel compares how much it varies with what is calm for you: less variation than your calm means more stress.",
        workedOut: nil
    )

    private static let highStress = Meaning(
        term: .highStress, title: "High stress",
        sections: [
            .init("What it is", "How many minutes of the day you spent at a high stress level."),
            .init("Good or bad", "At or under your usual is good; that's when your Stress dot sits inside your normal."),
            .init("A lot or a little", "One busy day above your usual is ordinary. Several in a row are worth a look."),
            .init("What's normal", "Your usual is worked out from your own last 28 counted days, never under 15 minutes."),
            .init("What affects it", "The same things as stress."),
        ],
        howTheBandKnows: "As for stress.",
        workedOut: nil
    )

    private static let heartRate = Meaning(
        term: .heartRate, title: "Heart rate",
        sections: [
            .init("What it is", "How many times your heart beats a minute, all day and night, from the Loop's 5-minute readings."),
            .init("Good or bad", "Neither. It should rise with effort and fall with rest."),
            .init(
                "A lot or a little",
                "Each day runs from its lowest (usually asleep) to its highest (your most active moment). A higher day's average than usual can come with an active day, heat, caffeine, stress or illness."
            ),
            .init("What's normal", "Awake at rest, 60 to 100 bpm for adults; lower asleep; much higher during exercise."),
            .init("What affects it", "Activity, standing up, caffeine, heat, stress, sleep, fitness, illness."),
        ],
        howTheBandKnows: "The Loop reads your pulse at the wrist every 5 minutes (every second during hard activity).",
        workedOut: nil
    )

    private static let heartFitness = Meaning(
        term: .heartFitness, title: "Heart fitness",
        sections: [
            .init(
                "What it is",
                "How your heart compares with other people your age: younger than your age, about your age, or older. It is worked out once a month from your resting heart rate while you sleep, your body (waist, or height and weight) and how many days a week the Loop counts you as exercising."
            ),
            .init(
                "Good or bad",
                "Younger than your age is the better side and older is the other side. Neither is a diagnosis, and it is only a comparison with your own age."),
            .init("What's normal", "\"About your age\" means within 5 years either side of your age. It moves slowly and changes only once a month."),
            .init(
                "What affects it",
                "Regular exercise, a lower resting heart rate, a smaller waist or weight for your height, and your age. Moderate and hard exercise move it more than anything else you can change."
            ),
            .init(
                "It's an estimate",
                "It comes from a population model, not a fitness test, and can be off by 10 years or more. Vesel measures your resting heart rate asleep, which is lower than the heart rate the model was built on, so the result leans younger. Look at where it heads over months, not at one month."
            ),
        ],
        howTheBandKnows:
            "The Loop gives your resting heart rate asleep and the minutes of moderate and hard movement. Your age, height, weight and waist come from About you. The band doesn't measure fitness itself.",
        workedOut: nil
    )

    private static let vo2max = Meaning(
        term: .vo2max, title: "VO2max",
        sections: [
            .init(
                "What it is",
                "The most oxygen your body can use in a minute at your hardest effort, per kilo of body weight (ml/kg/min). It is a common measure of how fit your heart and lungs are."
            ),
            .init("Good or bad", "Higher is generally better."),
            .init("What's normal", "It drops with age. Many adults are between about 30 and 50, and people who train hard go higher."),
            .init("What affects it", "Age, sex, genes, regular hard exercise, body weight and resting heart rate."),
            .init(
                "It's an estimate",
                "A lab test measures it. Vesel estimates it from your body, resting heart rate and exercise habits, and is often off by 5 or more either way. A device that uses your heart rate during exercise works it out another way, so the two numbers can differ."
            ),
        ],
        howTheBandKnows: "The Loop can't measure it. Vesel works it out from your resting heart rate asleep, your body and the Loop's minutes of exercise.",
        workedOut: nil
    )

    private static let steps = Meaning(
        term: .steps, title: "Steps",
        sections: [
            .init("What it is", "How many steps you took in a day, counted by the Loop's motion sensor."),
            .init("Good or bad", "Neither. It is a record of how much you moved, not a goal to reach."),
            .init("A lot or a little", "Days differ a lot with work, weather and plans. A day well under or over your usual is ordinary."),
            .init("What's normal", "Your own usual range: the middle band of your last 28 days. It needs 7 days before it shows."),
            .init("What affects it", "How much you walk, work, travel and exercise; a day you didn't wear the Loop counts few or none."),
        ],
        howTheBandKnows:
            "The Loop counts steps from the movement of your wrist. Arm movement without walking, or a day without the Loop, can make a count too high or too low. Vesel shows the total as it was when it last read your band, so today's number lags.",
        workedOut: nil
    )

    private static let howTheBandKnows = Meaning(
        term: .howTheBandKnows, title: "How the band knows",
        sections: [
            .init(
                "What it is",
                "The Loop shines light into the skin of your wrist and measures how much comes back. Each heartbeat pushes blood through and changes that, so the Loop can count beats and time the gap between them. It also has a motion sensor and a skin temperature sensor."
            ),
            .init(
                "Sleep stages are estimates",
                "A sleep lab reads brain waves; the Loop can't. Polar guesses stages from movement and heart rhythm. That's good for trends over many nights and rough for any single night."
            ),
            .init(
                "When it's less exact",
                "A loose band, a lot of movement or cold hands give noisier readings. For stress, Vesel drops beats the band marks as moving or not touching the skin."
            ),
            .init(
                "Where it goes",
                "Straight from the Loop to this iPhone over Bluetooth, and to your own Mac as a backup. Nothing passes through Polar's or anyone else's cloud."),
        ],
        howTheBandKnows: nil,
        workedOut: nil
    )
}
