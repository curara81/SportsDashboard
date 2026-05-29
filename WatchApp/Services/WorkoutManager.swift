import Foundation
import HealthKit
import WatchKit
import Combine

@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isActive = false
    @Published var isPaused = false
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var totalDistance: Double = 0       // meters
    @Published var currentPace: Double = 0         // seconds per km
    @Published var averagePace: Double = 0         // seconds per km
    @Published var currentHeartRate: Double = 0
    @Published var currentKm: Int = 0              // completed km count
    @Published var lastKmPace: Double = 0          // pace for last completed km
    @Published var paceStatus: PaceStatus = .onTarget

    // MARK: - Target Pace

    var targetPacePerKm: Double = 0                // seconds per km
    var paceToleranceSeconds: Double = 15           // alert if ± this much

    // MARK: - Pace Status

    enum PaceStatus: String {
        case tooFast = "빠름"
        case onTarget = "적정"
        case tooSlow = "느림"
    }

    // MARK: - Private

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let store = HKHealthStore()
    private var timer: Timer?
    private var startDate: Date?
    private var lastKmDistance: Double = 0
    private var lastKmTime: TimeInterval = 0
    private var lastHapticTime: Date = .distantPast

    // Minimum interval between haptic alerts (seconds)
    private let hapticCooldown: TimeInterval = 10

    // MARK: - Start Workout

    func startWorkout(targetPace: Double, tolerance: Double = 15) {
        self.targetPacePerKm = targetPace
        self.paceToleranceSeconds = tolerance

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            session = try HKWorkoutSession(healthStore: store, configuration: config)
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self

            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: config
            )

            let start = Date()
            session?.startActivity(with: start)
            builder?.beginCollection(withStart: start) { [weak self] success, error in
                guard success else { return }
                Task { @MainActor in
                    self?.startDate = start
                    self?.isActive = true
                    self?.isPaused = false
                    self?.startTimer()
                    WKInterfaceDevice.current().play(.start)
                }
            }
        } catch {
            print("Workout start failed: \(error)")
        }
    }

    // MARK: - Pause / Resume

    func pause() {
        session?.pause()
        isPaused = true
        WKInterfaceDevice.current().play(.stop)
    }

    func resume() {
        session?.resume()
        isPaused = false
        WKInterfaceDevice.current().play(.start)
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    // MARK: - End Workout

    func endWorkout() {
        session?.end()
        timer?.invalidate()
        timer = nil

        builder?.endCollection(withEnd: Date()) { [weak self] success, error in
            guard success else { return }
            self?.builder?.finishWorkout { workout, error in
                Task { @MainActor in
                    self?.isActive = false
                    self?.isPaused = false
                    WKInterfaceDevice.current().play(.success)
                }
            }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate, !self.isPaused else { return }
                self.elapsedSeconds = Date().timeIntervalSince(start)
                self.updatePaceMetrics()
            }
        }
    }

    // MARK: - Pace Calculation & Haptic

    private func updatePaceMetrics() {
        guard totalDistance > 0, elapsedSeconds > 0 else { return }

        // Average pace
        averagePace = elapsedSeconds / (totalDistance / 1000.0)

        // Check km milestone
        let completedKm = Int(totalDistance / 1000.0)
        if completedKm > currentKm {
            // New km completed
            let kmTime = elapsedSeconds - lastKmTime
            lastKmPace = kmTime / Double(completedKm - currentKm)
            lastKmTime = elapsedSeconds
            lastKmDistance = totalDistance
            currentKm = completedKm

            // Km milestone haptic
            WKInterfaceDevice.current().play(.notification)
        }

        // Rolling pace (last 200m or current km progress)
        let kmProgress = totalDistance - (Double(currentKm) * 1000.0)
        if kmProgress > 100 {
            let timeSinceLastKm = elapsedSeconds - lastKmTime
            currentPace = (timeSinceLastKm / kmProgress) * 1000.0
        } else {
            currentPace = averagePace
        }

        // Pace status check
        guard targetPacePerKm > 0 else { return }

        let diff = currentPace - targetPacePerKm
        let previousStatus = paceStatus

        if diff < -paceToleranceSeconds {
            paceStatus = .tooFast
        } else if diff > paceToleranceSeconds {
            paceStatus = .tooSlow
        } else {
            paceStatus = .onTarget
        }

        // Haptic alert on status change (with cooldown)
        if paceStatus != previousStatus && paceStatus != .onTarget {
            let now = Date()
            if now.timeIntervalSince(lastHapticTime) > hapticCooldown {
                lastHapticTime = now
                switch paceStatus {
                case .tooFast:
                    WKInterfaceDevice.current().play(.directionUp)
                case .tooSlow:
                    WKInterfaceDevice.current().play(.directionDown)
                case .onTarget:
                    break
                }
            }
        }
    }

    // MARK: - Reset

    func reset() {
        elapsedSeconds = 0
        totalDistance = 0
        currentPace = 0
        averagePace = 0
        currentHeartRate = 0
        currentKm = 0
        lastKmPace = 0
        lastKmDistance = 0
        lastKmTime = 0
        paceStatus = .onTarget
        isActive = false
        isPaused = false
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // State tracking handled via published properties
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("Workout session error: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType else { continue }

                let statistics = workoutBuilder.statistics(for: quantityType)

                switch quantityType {
                case HKQuantityType(.heartRate):
                    let unit = HKUnit.count().unitDivided(by: .minute())
                    self.currentHeartRate = statistics?.mostRecentQuantity()?.doubleValue(for: unit) ?? 0

                case HKQuantityType(.distanceWalkingRunning):
                    self.totalDistance = statistics?.sumQuantity()?.doubleValue(for: .meter()) ?? 0

                default:
                    break
                }
            }
        }
    }
}
