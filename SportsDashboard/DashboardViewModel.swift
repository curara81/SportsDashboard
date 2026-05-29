import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {

    private let hk = HealthKitManager.shared

    @Published var readiness: MetricsEngine.ReadinessResult?
    @Published var hrvStatus: MetricsEngine.HRVStatus?
    @Published var trainingBalance: MetricsEngine.TrainingBalance?
    @Published var sleepHours: Double?
    @Published var restingHR: Double?
    @Published var latestHRV: Double?
    @Published var bodyMass: Double?
    @Published var bodyFatPercentage: Double?
    @Published var leanBodyMass: Double?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func authorize() async {
        do {
            try await hk.requestAuthorization()
        } catch {
            errorMessage = "HealthKit 권한 요청 실패: \(error.localizedDescription)"
        }
    }

    func loadMorningReport() async {
        isLoading = true
        errorMessage = nil

        do {
            async let sleepTask = hk.fetchLastNightSleep()
            async let hrvTask = hk.fetchHRV(daysBack: 21)
            async let rhrTask = hk.fetchRestingHeartRate(daysBack: 7)
            async let bodyTask = hk.fetchBodyComposition(daysBack: 90)

            let sleep = try await sleepTask
            let hrvValues = try await hrvTask
            let rhrValues = try await rhrTask
            let body = try await bodyTask

            self.sleepHours = sleep
            self.latestHRV = hrvValues.last?.value
            self.restingHR = rhrValues.last?.value
            self.bodyMass = hk.bodyMass
            self.bodyFatPercentage = hk.bodyFatPercentage
            self.leanBodyMass = hk.computedLeanBodyMass

            // HRV Status
            let status = MetricsEngine.evaluateHRVStatus(values: hrvValues)
            self.hrvStatus = status

            // Training Readiness
            let rhrAvg = rhrValues.map(\.value).reduce(0, +)
                / max(Double(rhrValues.count), 1)

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

        } catch {
            errorMessage = "데이터 로드 실패: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
