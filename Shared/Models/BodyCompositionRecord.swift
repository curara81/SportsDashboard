import Foundation
import SwiftData

@Model
final class BodyCompositionRecord {
    @Attribute(.unique) var date: Date
    var mass: Double
    var fatPercentage: Double?
    var leanMass: Double?

    var computedLeanMass: Double? {
        guard let fat = fatPercentage else { return leanMass }
        return mass * (1.0 - fat / 100.0)
    }

    init(date: Date, mass: Double, fatPercentage: Double? = nil, leanMass: Double? = nil) {
        self.date = date
        self.mass = mass
        self.fatPercentage = fatPercentage
        self.leanMass = leanMass
    }
}
