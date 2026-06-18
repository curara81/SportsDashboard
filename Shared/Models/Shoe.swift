import Foundation
import SwiftData

/// A pair of running shoes. Mileage = startKm + running distance logged since addedDate
/// (computed from HealthKit). Reminds you to retire it past retirementKm.
@Model
final class Shoe {
    var name: String
    var addedDate: Date
    var startKm: Double         // mileage already on the shoe when registered
    var retirementKm: Double    // suggested replacement threshold
    var isRetired: Bool

    init(name: String, startKm: Double = 0, retirementKm: Double = 800) {
        self.name = name
        self.addedDate = Date()
        self.startKm = startKm
        self.retirementKm = retirementKm
        self.isRetired = false
    }
}
