#if os(watchOS)
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
    @Published var averageHeartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var currentKm: Int = 0              // completed km count
    @Published var lastKmPace: Double = 0          // pace for last completed km
    @Published var paceStatus: PaceStatus = .onTarget
    @Published var currentSpeed: Double = 0        // m/s for cycling
    @Published var averageSpeed: Double = 0        // m/s for cycling

    // MARK: - Workout Type

    @Published var workoutType: SportType = .running

    enum SportType: String, CaseIterable, Identifiable {
        case running = "러닝"
        case walking = "걷기"
        case cycling = "사이클"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .running: return "figure.run"
            case .walking: return "figure.walk"
            case .cycling: return "figure.outdoor.cycle"
            }
        }

        var hkType: HKWorkoutActivityType {
            switch self {
            case .running: return .running
            case .walking: return .walking
            case .cycling: return .cycling
            }
        }

        var color: (r: Double, g: Double, b: Double) {
            switch self {
            case .running: return (0.3, 0.85, 0.45)
            case .walking: return (0.35, 0.65, 1.0)
            case .cycling: return (1.0, 0.65, 0.2)
            }
        }

        var usePace: Bool { self != .cycling }
    }

    // MARK: - Target Pace

    var targetPacePerKm: Double = 0                // seconds per km (0 = free mode)
    var paceToleranceSeconds: Double = 15

    var isFreeMode: Bool { targetPacePerKm <= 0 }

    // MARK: - Pace Status

    enum PaceStatus: String {
        case tooFast = "빠름"
        case onTarget = "적정"
        case tooSlow = "느림"
        case free = "자유"
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
    private var hrSamples: [Double] = []

    private let hapticCooldown: TimeInterval = 10

    private func playHaptic(_ type: Int) {
        #if os(watchOS)
        let hapticType: WKHapticType
        switch type {
        case 0: hapticType = .start
        case 1: hapticType = .stop
        case 2: hapticType = .success
        case 3: hapticType = .notification
        case 4: hapticType = .directionUp
        case 5: hapticType = .directionDown
        default: return
        }
        WKInterfaceDevice.current().play(hapticType)
        #endif
    }

    // MARK: - Start Workout

    func startWorkout(type: SportType, targetPace: Double = 0, tolerance: Double = 15) {
        self.workoutType = type
        self.targetPacePerKm = targetPace
        self.paceToleranceSeconds = tolerance
        self.paceStatus = targetPace > 0 ? .onTarget : .free

        let config = HKWorkoutConfiguration()
        config.activityType = type.hkType
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
                    self?.playHaptic(0) // start
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
        playHaptic(1) // stop
    }

    func resume() {
        session?.resume()
        isPaused = false
        playHaptic(0) // start
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
                    self?.playHaptic(2) // success
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
                self.updateMetrics()
            }
        }
    }

    // MARK: - Metrics Calculation

    private func updateMetrics() {
        guard totalDistance > 0, elapsedSeconds > 0 else { return }

        if workoutType.usePace {
            // Pace-based (running/walking)
            averagePace = elapsedSeconds / (totalDistance / 1000.0)

            let completedKm = Int(totalDistance / 1000.0)
            if completedKm > currentKm {
                let kmTime = elapsedSeconds - lastKmTime
                lastKmPace = kmTime / Double(completedKm - currentKm)
                lastKmTime = elapsedSeconds
                lastKmDistance = totalDistance
                currentKm = completedKm
                playHaptic(3) // notification
            }

            let kmProgress = totalDistance - (Double(currentKm) * 1000.0)
            if kmProgress > 100 {
                let timeSinceLastKm = elapsedSeconds - lastKmTime
                currentPace = (timeSinceLastKm / kmProgress) * 1000.0
            } else {
                currentPace = averagePace
            }
        } else {
            // Speed-based (cycling)
            currentSpeed = totalDistance / elapsedSeconds  // m/s
            averageSpeed = currentSpeed
        }

        // Average HR
        if currentHeartRate > 0 {
            hrSamples.append(currentHeartRate)
            averageHeartRate = hrSamples.reduce(0, +) / Double(hrSamples.count)
        }

        // Pace status check (only for pace-guided mode)
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

        if paceStatus != previousStatus && paceStatus != .onTarget {
            let now = Date()
            if now.timeIntervalSince(lastHapticTime) > hapticCooldown {
                lastHapticTime = now
                switch paceStatus {
                case .tooFast:
                    playHaptic(4) // directionUp
                case .tooSlow:
                    playHaptic(5) // directionDown
                default: break
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
        averageHeartRate = 0
        activeCalories = 0
        currentKm = 0
        lastKmPace = 0
        lastKmDistance = 0
        lastKmTime = 0
        currentSpeed = 0
        averageSpeed = 0
        paceStatus = .onTarget
        isActive = false
        isPaused = false
        hrSamples = []
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("Workout session error: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

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

                case HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling):
                    self.totalDistance = statistics?.sumQuantity()?.doubleValue(for: .meter()) ?? 0

                case HKQuantityType(.activeEnergyBurned):
                    self.activeCalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0

                default:
                    break
                }
            }
        }
    }
}
#endif
