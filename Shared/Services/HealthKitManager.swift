import Foundation
import HealthKit
import CoreLocation

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

    // Phase 3: new metrics
    @Published var vo2max: Double?
    @Published var recentVO2maxValues: [DatedValue] = []

    // Sleep stages
    @Published var sleepCore: Double?
    @Published var sleepDeep: Double?
    @Published var sleepREM: Double?
    @Published var sleepAwake: Double?

    // Running dynamics
    @Published var lastRunningPower: Double?
    @Published var lastCadence: Double?
    @Published var lastGCT: Double?           // ground contact time ms
    @Published var lastVerticalOsc: Double?    // vertical oscillation cm
    @Published var lastStrideLength: Double?   // meters

    // MARK: - Authorization

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        let identifiers: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRateVariabilitySDNN, .heartRate,
            .vo2Max, .bodyMass, .bodyFatPercentage, .leanBodyMass,
            .distanceWalkingRunning, .activeEnergyBurned, .runningSpeed,
            .stepCount, .appleExerciseTime
        ]
        for id in identifiers {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        // GPS workout route — required to READ saved routes for the post-workout
        // map / flyover. Without this the route query returns empty ("GPS 경로 없음").
        types.insert(HKSeriesType.workoutRoute())
        return types
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Note: HKWorkoutSession handles its own write authorization.
        // Share types omitted to avoid NSException from purpose string validation
        // on certain simulator/OS versions.
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Sleep

    struct DailyActivity {
        var steps: Double = 0
        var distanceKm: Double = 0
        var activeCalories: Double = 0
        var exerciseMinutes: Double = 0
    }

    /// Today's cumulative activity totals (since local midnight).
    func fetchTodayActivity() async throws -> DailyActivity {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
            await withCheckedContinuation { cont in
                let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                    cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
                }
                store.execute(q)
            }
        }

        var a = DailyActivity()
        a.steps = await sum(.stepCount, unit: .count())
        a.distanceKm = await sum(.distanceWalkingRunning, unit: .meter()) / 1000.0
        a.activeCalories = await sum(.activeEnergyBurned, unit: .kilocalorie())
        a.exerciseMinutes = await sum(.appleExerciseTime, unit: .minute())
        return a
    }

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

    /// Asleep hours per night for the last `nights` nights (oldest→newest), bucketed
    /// by wake day. For the Sleep Bank (sleep-debt) calculation.
    func fetchNightlySleepHours(nights: Int = 7) async -> [Double] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -nights, to: cal.startOfDay(for: end)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples = (try? await queryCategorySamples(type: sleepType, predicate: predicate)) ?? []

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]
        var byDay: [Date: Double] = [:]
        for s in samples where asleep.contains(s.value) {
            let day = cal.startOfDay(for: s.endDate)   // attribute to wake day
            byDay[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }
        var out: [Double] = []
        for i in stride(from: nights - 1, through: 0, by: -1) {
            if let day = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: end)) {
                out.append((byDay[day] ?? 0) / 3600.0)
            }
        }
        return out
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

    /// Daily step totals for the last `daysBack` days (startOfDay → steps). For the calendar.
    func fetchDailySteps(daysBack: Int = 40) async -> [Date: Double] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [:] }
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date())
        var interval = DateComponents(); interval.day = 1
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: stepType, quantitySamplePredicate: nil,
                options: .cumulativeSum, anchorDate: anchor, intervalComponents: interval)
            q.initialResultsHandler = { _, results, _ in
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: anchor, to: Date()) { stat, _ in
                    if let sum = stat.sumQuantity()?.doubleValue(for: .count()) {
                        out[cal.startOfDay(for: stat.startDate)] = sum
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Best recent run for race prediction: the running workout (>=2km) with the
    /// fastest average pace in the last `daysBack` days. Returns (distanceKm, time).
    func fetchBestRecentRun(daysBack: Int = 90) async throws -> (distanceKm: Double, time: TimeInterval)? {
        let workouts = try await fetchWorkouts(daysBack: daysBack)
        let runs = workouts.filter { $0.workoutActivityType == .running }

        var best: (km: Double, time: TimeInterval, pace: Double)?
        for w in runs {
            let meters: Double
            if let s = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) {
                meters = s
            } else if #available(watchOS 10.0, iOS 16.0, *), let d = w.totalDistance?.doubleValue(for: .meter()) {
                meters = d
            } else { continue }

            let km = meters / 1000.0
            let dur = w.duration
            guard km >= 2.0, dur > 0 else { continue }
            let pace = dur / km   // sec per km
            if best == nil || pace < best!.pace {
                best = (km, dur, pace)
            }
        }
        guard let b = best else { return nil }
        return (b.km, b.time)
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

    // MARK: - VO2max

    func fetchVO2max(daysBack: Int = 90) async throws -> [DatedValue] {
        let vo2Type = HKQuantityType(.vo2Max)
        let unit = HKUnit(from: "ml/kg*min")
        let values = try await fetchDatedValues(type: vo2Type, unit: unit, daysBack: daysBack)
        self.recentVO2maxValues = values
        self.vo2max = values.last?.value
        return values
    }

    // MARK: - Sleep Stages

    func fetchSleepStages() async throws -> (core: Double, deep: Double, rem: Double, awake: Double) {
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

        var core = 0.0, deep = 0.0, rem = 0.0, awake = 0.0

        for sample in samples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                core += duration
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deep += duration
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                rem += duration
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awake += duration
            default:
                break
            }
        }

        self.sleepCore = core
        self.sleepDeep = deep
        self.sleepREM = rem
        self.sleepAwake = awake

        return (core, deep, rem, awake)
    }

    // MARK: - Running Dynamics (for a specific workout)

    func fetchRunningDynamics(for workout: HKWorkout) async throws {
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate, options: .strictStartDate
        )

        // Running Power
        if let powerSamples = try? await queryQuantitySamples(
            type: HKQuantityType(.runningPower), predicate: predicate
        ), !powerSamples.isEmpty {
            let avg = powerSamples.map { $0.quantity.doubleValue(for: .watt()) }.reduce(0, +) / Double(powerSamples.count)
            self.lastRunningPower = avg
        }

        // Ground Contact Time
        if let gctSamples = try? await queryQuantitySamples(
            type: HKQuantityType(.runningGroundContactTime), predicate: predicate
        ), !gctSamples.isEmpty {
            let avg = gctSamples.map { $0.quantity.doubleValue(for: .secondUnit(with: .milli)) }.reduce(0, +) / Double(gctSamples.count)
            self.lastGCT = avg
        }

        // Vertical Oscillation
        if let voSamples = try? await queryQuantitySamples(
            type: HKQuantityType(.runningVerticalOscillation), predicate: predicate
        ), !voSamples.isEmpty {
            let unit = HKUnit.meterUnit(with: .centi)
            let avg = voSamples.map { $0.quantity.doubleValue(for: unit) }.reduce(0, +) / Double(voSamples.count)
            self.lastVerticalOsc = avg
        }

        // Stride Length
        if let slSamples = try? await queryQuantitySamples(
            type: HKQuantityType(.runningStrideLength), predicate: predicate
        ), !slSamples.isEmpty {
            let avg = slSamples.map { $0.quantity.doubleValue(for: .meter()) }.reduce(0, +) / Double(slSamples.count)
            self.lastStrideLength = avg
        }
    }

    // MARK: - Workout Route (GPS)

    func fetchWorkoutRoute(for workout: HKWorkout) async throws -> [CLLocation] {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)

        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: results as? [HKWorkoutRoute] ?? [])
            }
            store.execute(query)
        }

        guard let route = routes.first else { return [] }

        return try await withCheckedThrowingContinuation { cont in
            var allLocations: [CLLocation] = []
            let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let locations { allLocations.append(contentsOf: locations) }
                if done { cont.resume(returning: allLocations) }
            }
            store.execute(routeQuery)
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
