import Foundation
import SwiftData

@Model
final class DailyReadiness {
    @Attribute(.unique) var date: Date
    var score: Double
    var sleepScore: Double
    var hrvScore: Double
    var rhrScore: Double
    var label: String
    var sleepHours: Double
    var hrvValue: Double
    var rhrValue: Double

    init(date: Date, score: Double = 0, sleepScore: Double = 0,
         hrvScore: Double = 0, rhrScore: Double = 0, label: String = "",
         sleepHours: Double = 0, hrvValue: Double = 0, rhrValue: Double = 0) {
        self.date = date
        self.score = score
        self.sleepScore = sleepScore
        self.hrvScore = hrvScore
        self.rhrScore = rhrScore
        self.label = label
        self.sleepHours = sleepHours
        self.hrvValue = hrvValue
        self.rhrValue = rhrValue
    }
}
