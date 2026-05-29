import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    @Published var sleepHours: Double?
    @Published var restingHeartRate: Double?
    @Published var hrvSDNN: Double?
    @Published var recentHRVValues: [DatedValue] = []
    @Published var recentRHRValues: [DatedValue] = []
    @Published var bodyMass: Double?
    @Published var bodyFatPercentage: Double?
    @Published var leanBodyMass: Double?
    @Published var recentBodyMassValues: [DatedValue] = []
    @Published var recentBodyFatValues: [DatedValue] = []

    // MARK: - Authorization

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        let identifiers: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRateVariabilitySDNN, .heartRate,
            .vo2Max, .bodyMass, .bodyFatPercentage, .leanBodyMass,
            .distanceWalkingRunning, .activeEnergyBurned, .runningSpeed
        ]
        for id in identifiers {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Sleep

    func fetchLastNightSleep() async throws -> Double {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current
        let now = Date()
        let sixPMYesterday = calendar.date(
            bySettingHour: 18, minute: 0, second: 0,
            of: calendar.date(byAdding: .day, value: -1, to: now)!
        )!
        let predicate = HKQuery.predicateForSamples(
            withStart: sixPMYesterday, end: now, options: .strictStartDate
        )

        let samples = try await queryCategorySamples(type: sleepType, predicate: predicate)

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]

        let totalSeconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

        let hours = totalSeconds / 3600.0
        self.sleepHours = hours
        return hours
    }

    // MARK: - Resting Heart Rate

    func fetchRestingHeartRate(daysBack: Int = 7) async throws -> [DatedValue] {
        let rhrType = HKQuantityType(.restingHeartRate)
        let values = try await fetchDatedValues(
            type: rhrType, unit: .count().unitDivided(by: .minute()), daysBack: daysBack
        )
        self.recentRHRValues = values
        self.restingHeartRate = values.last?.value
        return values
    }

    // MARK: - HRV

    func fetchHRV(daysBack: Int = 21) async throws -> [DatedValue] {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let values = try await fetchDatedValues(
            type: hrvType, unit: .secondUnit(with: .milli), daysBack: daysBack
        )
        self.recentHRVValues = values
        self.hrvSDNN = values.last?.value
        return values
    }

    // MARK: - Body Composition

    func fetchBodyComposition(daysBack: Int = 90) async throws -> (mass: [DatedValue], fat: [DatedValue]) {
        let massValues = try await fetchDatedValues(
            type: HKQuantityType(.bodyMass), unit: .gramUnit(with: .kilo), daysBack: daysBack
        )
        let fatValues = try await fetchDatedValues(
            type: HKQuantityType(.bodyFatPercentage), unit: .percent(), daysBack: daysBack,
            transform: { $0 * 100 }
        )
        let leanValues = try await fetchDatedValues(
            type: HKQuantityType(.leanBodyMass), unit: .gramUnit(with: .kilo), daysBack: daysBack
        )

        self.recentBodyMassValues = massValues
        self.recentBodyFatValues = fatValues
        self.bodyMass = massValues.last?.value
        self.bodyFatPercentage = fatValues.last?.value
        self.leanBodyMass = leanValues.last?.value

        return (massValues, fatValues)
    }

    var computedLeanBodyMass: Double? {
        guard let mass = bodyMass, let fat = bodyFatPercentage else { return leanBodyMass }
        return mass * (1.0 - fat / 100.0)
    }

    // MARK: - Workouts (Phase 2: read existing workouts for TRIMP)

    func fetchWorkouts(daysBack: Int = 90) async throws -> [HKWorkout] {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -daysBack, to: end)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: results as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
    }

    func fetchHeartRateSamples(for workout: HKWorkout) async throws -> [DatedValue] {
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate, options: .strictStartDate
        )
        let samples = try await queryQuantitySamples(type: hrType, predicate: predicate)
        return samples.map {
            DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
        }
    }

    // MARK: - Helpers

    private func fetchDatedValues(
        type: HKQuantityType, unit: HKUnit, daysBack: Int, transform: ((Double) -> Double)? = nil
    ) async throws -> [DatedValue] {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -daysBack, to: end)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples = try await queryQuantitySamples(type: type, predicate: predicate)
        return samples.map {
            let raw = $0.quantity.doubleValue(for: unit)
            return DatedValue(date: $0.startDate, value: transform?(raw) ?? raw)
        }
    }

    private func queryQuantitySamples(type: HKQuantityType, predicate: NSPredicate) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: results as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
    }

    private func queryCategorySamples(type: HKCategoryType, predicate: NSPredicate) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: results as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }
    }
}
