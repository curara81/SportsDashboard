import Foundation
import SwiftData
import HealthKit

@MainActor
final class DashboardViewModel: ObservableObject {

    private let hk = HealthKitManager.shared

    @Published var readiness: MetricsEngine.ReadinessResult?
    @Published var hrvStatus: MetricsEngine.HRVStatus?
    @Published var trainingBalance: MetricsEngine.TrainingBalance?
    @Published var acwr: Double = 0
    @Published var acwrLabel: String = ""
    @Published var sleepHours: Double?
    @Published var restingHR: Double?
    @Published var latestHRV: Double?
    @Published var bodyMass: Double?
    @Published var bodyFatPercentage: Double?
    @Published var leanBodyMass: Double?
    @Published var recentLoads: [DailyTrainingLoad] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func authorize() async {
        do {
            try await hk.requestAuthorization()
        } catch {
            errorMessage = "HealthKit 권한 요청 실패: \(error.localizedDescription)"
        }
    }

    func loadMorningReport(context: ModelContext) async {
        isLoading = true
        errorMessage = nil

        #if targetEnvironment(simulator)
        loadMockData(context: context)
        #else
        do {
            async let sleepTask = hk.fetchLastNightSleep()
            async let hrvTask = hk.fetchHRV(daysBack: 21)
            async let rhrTask = hk.fetchRestingHeartRate(daysBack: 7)
            async let bodyTask = hk.fetchBodyComposition(daysBack: 90)

            let sleep = try await sleepTask
            let hrvValues = try await hrvTask
            let rhrValues = try await rhrTask
            _ = try await bodyTask

            self.sleepHours = sleep
            self.latestHRV = hrvValues.last?.value
            self.restingHR = rhrValues.last?.value
            self.bodyMass = hk.bodyMass
            self.bodyFatPercentage = hk.bodyFatPercentage
            self.leanBodyMass = hk.computedLeanBodyMass

            let status = MetricsEngine.evaluateHRVStatus(values: hrvValues)
            self.hrvStatus = status

            let rhrAvg = rhrValues.map(\.value).reduce(0, +) / max(Double(rhrValues.count), 1)

            if let todayHRV = hrvValues.last?.value,
               let todayRHR = rhrValues.last?.value {
                self.readiness = MetricsEngine.calculateReadiness(
                    sleepHours: sleep,
                    todayHRV: todayHRV,
                    hrvBaseline: status.baseline,
                    hrvLowerBound: status.lowerBound,
                    todayRHR: todayRHR,
                    rhrSevenDayAvg: rhrAvg
                )
            }

            await processWorkouts(context: context)

        } catch {
            errorMessage = "데이터 로드 실패: \(error.localizedDescription)"
        }
        #endif

        isLoading = false
    }

    // MARK: - Mock Data (Simulator Only)

    #if targetEnvironment(simulator)
    private func loadMockData(context: ModelContext) {
        self.sleepHours = 7.2
        self.restingHR = 52
        self.latestHRV = 48
        self.bodyMass = 72.5
        self.bodyFatPercentage = 15.8
        self.leanBodyMass = 61.0

        let now = Date()
        let cal = Calendar.current

        var hrvValues: [DatedValue] = []
        for i in 0..<21 {
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            let value = 42.0 + Double.random(in: -8...12)
            hrvValues.append(DatedValue(date: date, value: value))
        }
        self.hrvStatus = MetricsEngine.evaluateHRVStatus(values: hrvValues)

        var rhrValues: [DatedValue] = []
        for i in 0..<14 {
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            let value = 50.0 + Double.random(in: -3...5)
            rhrValues.append(DatedValue(date: date, value: value))
        }
        HealthKitManager.shared.recentRHRValues = rhrValues
        HealthKitManager.shared.recentHRVValues = hrvValues

        self.readiness = MetricsEngine.calculateReadiness(
            sleepHours: 7.2,
            todayHRV: 48,
            hrvBaseline: hrvStatus?.baseline ?? 45,
            hrvLowerBound: hrvStatus?.lowerBound ?? 35,
            todayRHR: 52,
            rhrSevenDayAvg: 51
        )

        let trimpValues: [Double] = [85, 120, 0, 65, 140, 95, 0,
                                      70, 110, 0, 80, 130, 100, 0,
                                      90, 115, 0, 75, 125, 105, 0,
                                      60, 135, 0, 85, 110, 95, 0,
                                      70, 120]

        var ctl = 0.0, atl = 0.0, acuteE = 0.0, chronicE = 0.0
        var loads: [DailyTrainingLoad] = []

        for (i, trimp) in trimpValues.enumerated() {
            let date = cal.date(byAdding: .day, value: -(trimpValues.count - 1 - i), to: now)!
            let dayStart = cal.startOfDay(for: date)

            let balance = MetricsEngine.updateCTLATL(previousCTL: ctl, previousATL: atl, todayLoad: trimp)
            ctl = balance.ctl; atl = balance.atl

            let acwr = MetricsEngine.updateACWR(previousAcute: acuteE, previousChronic: chronicE, todayLoad: trimp)
            acuteE = acwr.acute; chronicE = acwr.chronic

            let load = DailyTrainingLoad(date: dayStart, trimp: trimp, durationMinutes: trimp > 0 ? trimp * 0.5 : 0)
            load.ctl = ctl; load.atl = atl; load.tsb = balance.tsb
            load.acwrAcute = acuteE; load.acwrChronic = chronicE
            load.workoutType = trimp > 0 ? "러닝" : nil
            load.avgHR = trimp > 0 ? 145 + Double.random(in: -10...10) : nil
            load.maxHR = trimp > 0 ? 172 + Double.random(in: -5...8) : nil
            loads.append(load)
        }

        self.recentLoads = loads

        if let last = loads.last {
            self.trainingBalance = MetricsEngine.TrainingBalance(
                ctl: last.ctl, atl: last.atl, tsb: last.tsb,
                label: last.tsb > 10 ? "최상 컨디션" : last.tsb >= -10 ? "보통" : "피로 누적"
            )
            self.acwr = chronicE > 0 ? acuteE / chronicE : 0
            self.acwrLabel = MetricsEngine.acwrZone(self.acwr)
        }
    }
    #endif

    // MARK: - Workout Processing (Phase 2 core)

    private func processWorkouts(context: ModelContext) async {
        do {
            let profile = fetchOrCreateProfile(context: context)
            let workouts = try await hk.fetchWorkouts(daysBack: 90)

            for workout in workouts {
                let dayStart = Calendar.current.startOfDay(for: workout.startDate)

                let descriptor = FetchDescriptor<DailyTrainingLoad>(
                    predicate: #Predicate { $0.date == dayStart }
                )
                let existing = try context.fetch(descriptor)
                if !existing.isEmpty { continue }

                let hrSamples = try await hk.fetchHeartRateSamples(for: workout)
                guard !hrSamples.isEmpty else { continue }

                let trimp = MetricsEngine.calculateTRIMP(
                    hrSamples: hrSamples,
                    restingHR: profile.restingHR,
                    maxHR: profile.effectiveMaxHR,
                    isMale: profile.isMale
                )

                let avgHR = hrSamples.map(\.value).reduce(0, +) / Double(hrSamples.count)
                let maxHR = hrSamples.map(\.value).max() ?? 0

                let load = DailyTrainingLoad(
                    date: dayStart,
                    trimp: trimp,
                    durationMinutes: workout.duration / 60.0
                )
                load.avgHR = avgHR
                load.maxHR = maxHR
                load.workoutType = workout.workoutActivityType.name
                context.insert(load)
            }

            try context.save()
            updateTrainingMetrics(context: context)

        } catch {
            errorMessage = "운동 데이터 처리 실패: \(error.localizedDescription)"
        }
    }

    private func updateTrainingMetrics(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<DailyTrainingLoad>(
                sortBy: [SortDescriptor(\.date)]
            )
            let allLoads = try context.fetch(descriptor)
            self.recentLoads = allLoads

            var ctl = 0.0
            var atl = 0.0
            var acuteEWMA = 0.0
            var chronicEWMA = 0.0

            for load in allLoads {
                let balance = MetricsEngine.updateCTLATL(
                    previousCTL: ctl, previousATL: atl, todayLoad: load.trimp
                )
                ctl = balance.ctl
                atl = balance.atl
                load.ctl = ctl
                load.atl = atl
                load.tsb = balance.tsb

                let acwrResult = MetricsEngine.updateACWR(
                    previousAcute: acuteEWMA, previousChronic: chronicEWMA, todayLoad: load.trimp
                )
                acuteEWMA = acwrResult.acute
                chronicEWMA = acwrResult.chronic
                load.acwrAcute = acuteEWMA
                load.acwrChronic = chronicEWMA
            }

            try context.save()

            if let last = allLoads.last {
                self.trainingBalance = MetricsEngine.TrainingBalance(
                    ctl: last.ctl, atl: last.atl, tsb: last.tsb,
                    label: last.tsb > 10 ? "최상 컨디션" : last.tsb >= -10 ? "보통" : "피로 누적"
                )
                self.acwr = chronicEWMA > 0 ? acuteEWMA / chronicEWMA : 0
                self.acwrLabel = MetricsEngine.acwrZone(self.acwr)
            }
        } catch {
            errorMessage = "메트릭 업데이트 실패: \(error.localizedDescription)"
        }
    }

    private func fetchOrCreateProfile(context: ModelContext) -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>()
        if let existing = try? context.fetch(descriptor).first { return existing }
        let profile = UserProfile()
        if let rhr = restingHR { profile.restingHR = rhr }
        context.insert(profile)
        return profile
    }
}

// MARK: - HKWorkoutActivityType Name

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "러닝"
        case .cycling: return "사이클링"
        case .swimming: return "수영"
        case .walking: return "걷기"
        case .hiking: return "등산"
        case .yoga: return "요가"
        case .functionalStrengthTraining: return "근력 운동"
        case .traditionalStrengthTraining: return "웨이트"
        case .coreTraining: return "코어"
        case .elliptical: return "일립티컬"
        case .rowing: return "로잉"
        default: return "기타"
        }
    }
}
