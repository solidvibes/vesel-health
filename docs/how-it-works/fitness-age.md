# Fitness age

**Status:** Built. Planned: the card moves to Body.

> An estimate of how fit your heart is for your age, from your resting heart rate, body size and activity.

## Intent
A slow, explainable sense of how your heart is ageing, without a score to chase.

## How it works
Body has a Heart fitness card, after the signal groups. Once a month (on the 1st) Vesel works out an estimate for the month before: the 28 days ending on its last day. Nothing is stored, no alert, nothing on Today or in widgets, and no change from last month is shown.

It needs 7 nights of resting heart rate and 14 worn days (a day with a daily summary and under 4 hours not worn) in that month; until then the card says when it will be worked out. Ages 20 to 90 only.

The estimate is the Norwegian HUNT study's model without exercise testing (Nes et al. 2011, 2014). With a waist in About you it uses the waist model (Nes 2011, reprinted in PMC7428991; the NTNU calculator uses the same):
- Men: VO2max = 100.27 − 0.296·age + 0.226·activity index − 0.369·waist cm − 0.155·resting HR (R² 0.61, SEE 5.70).
- Women: VO2max = 74.736 − 0.247·age + 0.198·activity index − 0.259·waist cm − 0.114·resting HR (R² 0.56, SEE 5.14).

Without a waist it uses BMI in place of waist:
- Men: VO2max = 92.05 − 0.327·age − 0.933·BMI − 0.167·resting HR + 0.257·activity index.
- Women: VO2max = 70.77 − 0.244·age − 0.749·BMI − 0.107·resting HR + 0.213·activity index.
- Fitness age = 160.7 − 2.513·VO2max (men) or 155.8 − 3.049·VO2max (women), capped at 80 below age 70 and 90 from 70, floored at 20, whole years (the NTNU/CERG calculator's formula).
- Age is the month's year minus birth year (it can be one too high). BMI is from About you. Resting heart rate is the median of the month's nights (measured asleep, so lower than the study's awake reading and the result leans younger).
- Activity index = frequency × duration × intensity, Vesel's mapping of the Loop's moderate and vigorous minutes onto the HUNT questionnaire. An exercise day has at least 15 minutes. Frequency (exercise days × 7 ÷ worn days): under 1 a week 0, 1 → 1, 2 to 3 → 2, 4 or more 3. Duration (median minutes on exercise days): under 30 → 1, 30 or more → 1.5. Intensity: 5 when at least half the exercise days have 10 minutes of vigorous time, else 1; never "all out" (the Loop can't tell).

What shows: a band, never the age. "About" is within 5 years either way; fitness age 6 or more years under your age is "Younger than your age", 6 or more over is "Older than your age". The page opens with the band in bold over its scale and three short lines (what it means, a band not an age, worked out once a month), then adds resting heart rate, exercise days a week, Vesel's estimated VO2max rounded ("about 50 ml/kg/min", often off by 5 or more) and "How it's worked out" (method `fitness.estimate` version 2: it names the model, input `model` 1 = waist, 0 = BMI), which holds the fitness age. Above its method it names the body measure used, in the chosen units: "Waist: 84 cm. Waist helps estimate your heart fitness. It stays on this phone.", or without a waist "BMI: 25.0, from your height and weight. Add your waist in About you and the estimate uses it instead."

A VO2max from another device (About you, optional, 10–90) is shown beside Vesel's estimate, "From your other device · 46 ml/kg/min", with one line on why they differ. It is never used in the estimate or the band, and never compared: no arrows, no verdict.

## Limits
- The coefficients are the models as reprinted in open HUNT papers, not read from the paywalled originals; the BMI version's error is not published. The waist version's is 5.1 to 5.7 ml/kg/min, 10 or more years of fitness age. The women's waist line comes from secondary sources only.
- The activity mapping is Vesel's own and moves the result more than anything else you can change.
- Resting heart rate asleep leans it younger.

## Constraints
- Never a score to chase (`docs/decisions/2026-10-27-no-score-to-chase.md`): no age on screen, no streaks, no bests, no month-to-month arrows.
- Worked out on read in VeselCore (`FitnessAge`) from the profile, the stored resting heart rate nights and the class seconds in the daily summary kept in `raw_export`. Waist and the outside VO2max are two nullable `profile` columns (migration `v4`), backed up to the Mac with the rest of the profile; nothing worked out is stored.
- Reduce Motion: the marker is shown settled, no slide.
