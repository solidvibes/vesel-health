import Testing
import VeselCore

struct UnitsTests {
    @Test func usUnitsConvertFromTheStoredMetricValues() {
        // 75 × 2.20462 = 165.3; 180 ÷ 2.54 = 70.9 → 71 in = 5 ft 11 in; 84 ÷ 2.54 = 33.1; 34.6 × 9 ÷ 5 + 32 = 94.28.
        #expect(Units.us.weightText(kg: 75) == "165 lb")
        #expect(Units.us.heightText(cm: 180) == "5 ft 11 in")
        #expect(Units.us.waistText(cm: 84) == "33 in")
        #expect(Units.us.temperatureText(celsius: 34.6) == "94.3 °F")
        #expect(Units.us.temperatureDifferenceText(celsius: 0.2) == "+0.4 °F")
        #expect(Units.us.temperatureDifferenceText(celsius: -0.2) == "−0.4 °F")
        // 8 400 m ÷ 1 609.344 = 5.22 mi; 11.9 km/h = 11 900 ÷ 1 609.344 = 7.39 mph.
        #expect(Units.us.distanceText(meters: 8_400) == "5.2 mi")
        #expect(Units.us.speedText(kmh: 11.9) == "7.4 mph")
    }

    @Test func metricShowsTheStoredValues() {
        #expect(Units.metric.weightText(kg: 75) == "75 kg")
        #expect(Units.metric.heightText(cm: 180) == "180 cm")
        #expect(Units.metric.waistText(cm: 84) == "84 cm")
        #expect(Units.metric.temperatureText(celsius: 34.6) == "34.6 °C")
        #expect(Units.metric.temperatureDifferenceText(celsius: 0.2) == "+0.2 °C")
        #expect(Units.metric.distanceText(meters: 8_400) == "8.4 km")
        #expect(Units.metric.speedText(kmh: 11.94) == "11.9 km/h")
    }
}
