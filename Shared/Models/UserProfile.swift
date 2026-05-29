import Foundation
import SwiftData

@Model
final class UserProfile {
    var maxHR: Double
    var restingHR: Double
    var isMale: Bool
    var birthYear: Int
    var vt1HeartRate: Double?
    var vt2HeartRate: Double?
    var targetSleepHours: Double

    var age: Int {
        Calendar.current.component(.year, from: Date()) - birthYear
    }

    var estimatedMaxHR: Double {
        208.0 - (0.7 * Double(age))
    }

    var effectiveMaxHR: Double {
        maxHR > 0 ? maxHR : estimatedMaxHR
    }

    var heartRateReserve: Double {
        effectiveMaxHR - restingHR
    }

    func karvonenZone(_ percentage: Double) -> Double {
        (heartRateReserve * percentage) + restingHR
    }

    var zones: [(name: String, lower: Double, upper: Double)] {
        [
            ("Z1 회복", karvonenZone(0.50), karvonenZone(0.60)),
            ("Z2 유산소", karvonenZone(0.60), karvonenZone(0.70)),
            ("Z3 템포", karvonenZone(0.70), karvonenZone(0.80)),
            ("Z4 VO2max", karvonenZone(0.80), karvonenZone(0.90)),
            ("Z5 무산소", karvonenZone(0.90), effectiveMaxHR)
        ]
    }

    init(maxHR: Double = 0, restingHR: Double = 60, isMale: Bool = true,
         birthYear: Int = 1990, targetSleepHours: Double = 8.0) {
        self.maxHR = maxHR
        self.restingHR = restingHR
        self.isMale = isMale
        self.birthYear = birthYear
        self.targetSleepHours = targetSleepHours
    }
}
