import Foundation
import SwiftData

@Model
final class DailyTrainingLoad {
    @Attribute(.unique) var date: Date
    var trimp: Double
    var sessionRPE: Double?
    var durationMinutes: Double
    var avgHR: Double?
    var maxHR: Double?
    var workoutType: String?
    var ctl: Double
    var atl: Double
    var tsb: Double
    var acwrAcute: Double
    var acwrChronic: Double

    init(date: Date, trimp: Double = 0, durationMinutes: Double = 0) {
        self.date = date
        self.trimp = trimp
        self.durationMinutes = durationMinutes
        self.ctl = 0
        self.atl = 0
        self.tsb = 0
        self.acwrAcute = 0
        self.acwrChronic = 0
    }
}
