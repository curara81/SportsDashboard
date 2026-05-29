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
    @Published var authorizationStatus: AuthStatus = .unknown

    enum AuthStatus {
        case unknown, authorized, denied, unavailable
    }

    // MARK: - Authorization

    private let readTypes: Set<HKObjectType> = {
        guard let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
              let rhr = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
              let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let hr = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let vo2 = HKQuantityType.quantityType(forIdentifier: .vo2Max),
              let mass = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              let fat = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage),
              let lean = HKQuantityType.quantityType(forIdentifier: .leanBodyMass)
        else { return [] }
        return [sleep, rhr, hrv, hr, vo2, mass, fat, lean, HKObjectType.workoutType()]
    }()

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = .unavailable
            return
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        authorizationStatus = .authorized
    }

    // MARK: - Sleep (yesterday night)

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

        let samples = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: results as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }

        // AsleepCore + AsleepDeep + AsleepREM (exclude InBed, Awake)
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

    // MARK: - Resting Heart Rate (today / yesterday)

    func fetchRestingHeartRate(daysBack: Int = 7) async throws -> [DatedValue] {
        let rhrType = HKQuantityType(.restingHeartRate)
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -daysBack, to: end)!

        let samples = try await fetchQuantitySamples(type: rhrType, start: start, end: end)

        let values: [DatedValue] = samples.map {
            DatedValue(
                date: $0.startDate,
                value: $0.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            )
        }

        self.recentRHRValues = values
        self.restingHeartRate = values.last?.value
        return values
    }

    // MARK: - HRV SDNN (sleep-time samples, up to 21 days)

    func fetchHRV(daysBack: Int = 21) async throws -> [DatedValue] {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -daysBack, to: end)!

        let samples = try await fetchQuantitySamples(type: hrvType, start: start, end: end)

        let values: [DatedValue] = samples.map {
            DatedValue(
                date: $0.startDate,
                value: $0.quantity.doubleValue(for: .secondUnit(with: .milli))
            )
        }

        self.recentHRVValues = values
        self.hrvSDNN = values.last?.value
        return values
    }

    // MARK: - Body Composition

    func fetchBodyComposition(daysBack: Int = 90) async throws -> (mass: [DatedValue], fat: [DatedValue]) {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -daysBack, to: end)!

        let massType = HKQuantityType(.bodyMass)
        let fatType = HKQuantityType(.bodyFatPercentage)
        let leanType = HKQuantityType(.leanBodyMass)

        let massSamples = try await fetchQuantitySamples(type: massType, start: start, end: end)
        let fatSamples = try await fetchQuantitySamples(type: fatType, start: start, end: end)
        let leanSamples = try await fetchQuantitySamples(type: leanType, start: start, end: end)

        let massValues = massSamples.map {
            DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
        let fatValues = fatSamples.map {
            DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: .percent()) * 100)
        }

        self.recentBodyMassValues = massValues
        self.recentBodyFatValues = fatValues
        self.bodyMass = massValues.last?.value
        self.bodyFatPercentage = fatValues.last?.value
        self.leanBodyMass = leanSamples.last.map {
            $0.quantity.doubleValue(for: .gramUnit(with: .kilo))
        }

        return (massValues, fatValues)
    }

    var computedLeanBodyMass: Double? {
        guard let mass = bodyMass, let fat = bodyFatPercentage else { return leanBodyMass }
        return mass * (1.0 - fat / 100.0)
    }

    // MARK: - Helpers

    private func fetchQuantitySamples(
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { cont in
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
}

// MARK: - Data Model

struct DatedValue: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
