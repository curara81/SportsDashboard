#if os(watchOS)
import Foundation
import HealthKit
import WatchKit
import Combine
import CoreLocation

@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isActive = false
    @Published var isPaused = false
    @Published var isCountingDown = false
    @Published var isShowingSummary = false        // end → save/discard prompt
    @Published var countdownValue = 3

    // Frozen summary snapshot (so values don't change while user decides)
    @Published var summaryDuration: TimeInterval = 0
    @Published var summaryDistance: Double = 0
    @Published var summaryAvgPace: Double = 0
    @Published var summaryAvgHR: Double = 0
    @Published var summaryCalories: Double = 0
    @Published var summaryAscent: Double = 0
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

    // GPS / elevation
    @Published var totalAscent: Double = 0         // meters climbed
    @Published var totalDescent: Double = 0        // meters descended
    @Published var currentAltitude: Double = 0     // meters
    @Published var gpsAccuracy: CLLocationAccuracy = -1  // <0 = no fix yet
    @Published var hasGPSFix = false
    @Published var routePointCount = 0
    /// Live GPS trail for the in-workout map (drawn as a polyline). Mirrors the
    /// points fed to HKWorkoutRouteBuilder, kept in-memory for real-time display.
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []

    // Cadence
    @Published var currentCadence: Double = 0       // steps per minute

    // Running dynamics (HealthKit auto-collects these on outdoor runs, watchOS 9+)
    @Published var currentRunningPower: Double = 0        // watts
    @Published var currentStrideLength: Double = 0        // meters
    @Published var currentVerticalOscillation: Double = 0 // cm
    @Published var currentGroundContactTime: Double = 0   // ms

    // Laps (auto per-km + manual)
    @Published var laps: [Lap] = []
    @Published var currentLapDistance: Double = 0   // meters into current lap
    @Published var currentLapSeconds: TimeInterval = 0

    // HR zone time (seconds in each of 5 Karvonen zones)
    @Published var zoneSeconds: [TimeInterval] = [0, 0, 0, 0, 0]

    // Auto-pause
    @Published var autoPauseEnabled = true
    @Published var isAutoPaused = false

    struct Lap: Identifiable {
        let id = UUID()
        let index: Int
        let distance: Double        // meters
        let duration: TimeInterval  // seconds
        let avgHR: Double
        let avgPace: Double         // sec/km
        let ascent: Double          // meters
        let isManual: Bool
    }

    // Lap accumulators
    private var lapStartDistance: Double = 0
    private var lapStartTime: TimeInterval = 0
    private var lapStartAscent: Double = 0
    private var lapHRSamples: [Double] = []
    // HR zone boundaries (lower bound of each zone, Karvonen), injected at start
    private var zoneLowerBounds: [Double] = []
    // Auto-pause tracking
    private var lowSpeedSeconds = 0
    private var lastMetricDistance: Double = 0

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
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let store = HKHealthStore()
    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var startDate: Date?
    private var lastKmDistance: Double = 0
    private var lastKmTime: TimeInterval = 0
    private var lastHapticTime: Date = .distantPast
    private var hrSamples: [Double] = []
    private var lastAltitude: Double?           // for ascent/descent delta
    private var usesGPS = false                 // outdoor sports only

    private let hapticCooldown: TimeInterval = 10

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        // NOTE: allowsBackgroundLocationUpdates는 watchOS watch-only 앱에서
        // 설정 시 크래시 유발(UIBackgroundModes location 필요, WK앱엔 없음).
        // watchOS는 HKWorkoutSession이 백그라운드 위치를 자동 관리하므로 불필요.
    }

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

    /// zoneLowerBounds: 5 ascending Karvonen lower bounds [Z1,Z2,Z3,Z4,Z5] for live
    /// zone-time tracking. Pass UserProfile.zones.map(\.lower). Empty = no zone tracking.
    func startWorkout(type: SportType, targetPace: Double = 0, tolerance: Double = 15,
                      zoneLowerBounds: [Double] = []) {
        self.workoutType = type
        self.targetPacePerKm = targetPace
        self.paceToleranceSeconds = tolerance
        self.paceStatus = targetPace > 0 ? .onTarget : .free
        self.zoneLowerBounds = zoneLowerBounds

        // share(쓰기) 권한 필수: HKLiveWorkoutBuilder가 심박/거리/칼로리를 수집·저장하려면
        // toShare 필요. 이전 크래시는 NSHealthUpdateUsageDescription 문자열이 너무 짧아
        // watchOS가 "invalid value" 판정한 것 → Info.plist 문자열 길게 늘려 해결.
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
            // Required to SAVE the GPS route via HKWorkoutRouteBuilder.finishRoute.
            // Missing here = route silently never persists → detail shows "GPS 경로 없음".
            HKSeriesType.workoutRoute()
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.runningPower),
            HKQuantityType(.runningStrideLength),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.stepCount),
            HKObjectType.workoutType()
        ]
        // Request location permission up front (GPS route needs it).
        locationManager.requestWhenInUseAuthorization()

        store.requestAuthorization(toShare: share, read: read) { [weak self] _, authErr in
            if let authErr = authErr {
                print("HealthKit auth error: \(authErr.localizedDescription)")
            }
            Task { @MainActor in
                self?.beginCountdown(type: type)
            }
        }
    }

    // MARK: - Countdown (3-2-1 before start)

    @MainActor
    private func beginCountdown(type: SportType) {
        countdownTimer?.invalidate()
        isCountingDown = true
        countdownValue = 3
        playHaptic(3) // notification tick

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.countdownValue -= 1
                if self.countdownValue > 0 {
                    self.playHaptic(3) // tick
                } else {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    self.isCountingDown = false
                    self.beginSession(type: type)
                }
            }
        }
    }

    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isCountingDown = false
        countdownValue = 3
        playHaptic(1) // stop
    }

    @MainActor
    private func beginSession(type: SportType) {
        // Optimistic start: flip UI to active IMMEDIATELY so the workout screen
        // + timer always appear, regardless of whether HKWorkoutSession succeeds.
        // (Timer is wall-clock based; distance/HR fill in once the builder collects.)
        let start = Date()
        startDate = start
        isActive = true
        isPaused = false
        startTimer()
        playHaptic(0) // start

        // GPS for outdoor sports (run/walk/cycle all outdoor here).
        usesGPS = true
        if usesGPS {
            routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            locationManager.startUpdatingLocation()
        }

        let config = HKWorkoutConfiguration()
        config.activityType = type.hkType
        config.locationType = .outdoor

        do {
            session = try HKWorkoutSession(healthStore: store, configuration: config)
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self

            let dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: config
            )
            // Running dynamics aren't in the default collected set — enable them so
            // power/stride/vertical-oscillation/ground-contact stream live (run only).
            if type.hkType == .running {
                let dynamicIDs: [HKQuantityTypeIdentifier] = [
                    .runningPower, .runningStrideLength,
                    .runningVerticalOscillation, .runningGroundContactTime
                ]
                for id in dynamicIDs {
                    if let qt = HKQuantityType.quantityType(forIdentifier: id) {
                        dataSource.enableCollection(for: qt, predicate: nil)
                    }
                }
            }
            builder?.dataSource = dataSource

            session?.startActivity(with: start)
            builder?.beginCollection(withStart: start) { _, error in
                if let error = error {
                    print("beginCollection failed: \(error.localizedDescription)")
                }
            }
        } catch {
            // Session failed (e.g. permission), but UI is already active so the
            // user sees the timer running. Metrics just won't populate.
            print("Workout session start failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pause / Resume

    func pause() {
        session?.pause()
        isPaused = true
        if usesGPS { locationManager.stopUpdatingLocation() }
        playHaptic(1) // stop
    }

    func resume() {
        session?.resume()
        isPaused = false
        if usesGPS { locationManager.startUpdatingLocation() }
        playHaptic(0) // start
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    // MARK: - End Workout (stop → summary → save/discard)

    /// Stops live tracking and shows the summary screen. Does NOT yet write to
    /// HealthKit — the user chooses 저장(save) or 삭제(discard) from the summary.
    func endWorkout() {
        // Close the final partial lap so the summary shows complete lap data.
        if currentLapSeconds > 1 { recordLap(isManual: false) }

        // Freeze the summary snapshot before tearing down.
        summaryDuration = elapsedSeconds
        summaryDistance = totalDistance
        summaryAvgPace = averagePace
        summaryAvgHR = averageHeartRate
        summaryCalories = activeCalories
        summaryAscent = totalAscent

        // Stop the live UI + timers + GPS, switch to summary.
        isActive = false
        isPaused = false
        isCountingDown = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        timer?.invalidate()
        timer = nil
        if usesGPS { locationManager.stopUpdatingLocation() }

        // Pause the HK session so collection stops but the builder stays usable
        // for either save or discard.
        session?.pause()
        playHaptic(1) // stop

        isShowingSummary = true
    }

    /// User chose 저장: finalize the HK workout + attach GPS route.
    func saveWorkout() {
        playHaptic(2) // success
        isShowingSummary = false

        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, error in
            if let error = error {
                print("endCollection error: \(error.localizedDescription)")
            }
            self?.builder?.finishWorkout { workout, error in
                if let error = error {
                    print("finishWorkout error: \(error.localizedDescription)")
                    return
                }
                guard let workout = workout else { return }
                print("Workout saved to HealthKit ✓")
                self?.routeBuilder?.finishRoute(with: workout, metadata: nil) { route, rErr in
                    if let rErr = rErr {
                        print("finishRoute error: \(rErr.localizedDescription)")
                    } else if route != nil {
                        print("Route attached to workout ✓")
                    }
                    // 외부 운동 앱 연동은 직접 API 불필요:
                    // HKWorkout이 건강 앱에 저장되면 Apple 건강 연동을 지원하는
                    // 외부 앱이 자동으로 가져감. 우리는 풍부한 HKWorkout
                    // (거리/HR/칼로리/route)만 잘 쓰면 됨.
                }
            }
        }
        reset()
    }

    /// User chose 삭제: end the session WITHOUT saving anything to HealthKit.
    func discardWorkout() {
        playHaptic(1) // stop
        isShowingSummary = false

        session?.end()
        // End collection but DON'T call finishWorkout → nothing is persisted.
        builder?.endCollection(withEnd: Date()) { _, _ in
            // discardWorkout intentionally never finalizes; HK drops the partial.
        }
        builder?.discardWorkout()
        reset()
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

    // MARK: - Laps

    /// Close the current lap and start a new one. Called automatically each km,
    /// or manually via the lap button.
    func recordLap(isManual: Bool) {
        let dist = totalDistance - lapStartDistance
        let dur = elapsedSeconds - lapStartTime
        guard dur > 0 else { return }
        let avgHR = lapHRSamples.isEmpty ? 0 : lapHRSamples.reduce(0, +) / Double(lapHRSamples.count)
        let pace = dist > 0 ? dur / (dist / 1000.0) : 0
        let ascent = totalAscent - lapStartAscent

        laps.append(Lap(index: laps.count + 1, distance: dist, duration: dur,
                        avgHR: avgHR, avgPace: pace, ascent: ascent, isManual: isManual))

        // Reset lap accumulators
        lapStartDistance = totalDistance
        lapStartTime = elapsedSeconds
        lapStartAscent = totalAscent
        lapHRSamples = []
        currentLapDistance = 0
        currentLapSeconds = 0
        if isManual { playHaptic(3) }
    }

    // MARK: - Metrics Calculation

    private func updateMetrics() {
        guard totalDistance > 0, elapsedSeconds > 0 else { return }

        // --- Auto-pause: detect near-zero movement over 1s ticks ---
        if autoPauseEnabled && workoutType.usePace && !isPaused {
            let movedThisTick = totalDistance - lastMetricDistance
            if movedThisTick < 0.5 {            // <0.5 m in 1s ≈ stopped
                lowSpeedSeconds += 1
                if lowSpeedSeconds >= 3 && !isAutoPaused {
                    isAutoPaused = true
                    playHaptic(1)
                }
            } else {
                if isAutoPaused { isAutoPaused = false; playHaptic(0) }
                lowSpeedSeconds = 0
            }
        }
        lastMetricDistance = totalDistance

        // Speed (km/h) — computed for ALL types so walking/running show speed too
        currentSpeed = totalDistance / elapsedSeconds  // m/s
        averageSpeed = currentSpeed

        // --- HR zone time accumulation (1s per tick into the matching zone) ---
        if currentHeartRate > 0 && zoneLowerBounds.count == 5 && !isAutoPaused {
            var z = 0
            for (i, lb) in zoneLowerBounds.enumerated() where currentHeartRate >= lb { z = i }
            zoneSeconds[z] += 1
        }

        // --- Current lap live counters ---
        currentLapDistance = totalDistance - lapStartDistance
        currentLapSeconds = elapsedSeconds - lapStartTime
        if currentHeartRate > 0 { lapHRSamples.append(currentHeartRate) }

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
                // Auto-lap every completed km
                recordLap(isManual: false)
                playHaptic(3) // notification
            }

            let kmProgress = totalDistance - (Double(currentKm) * 1000.0)
            if kmProgress > 100 {
                let timeSinceLastKm = elapsedSeconds - lastKmTime
                currentPace = (timeSinceLastKm / kmProgress) * 1000.0
            } else {
                currentPace = averagePace
            }
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
        totalAscent = 0
        totalDescent = 0
        currentAltitude = 0
        gpsAccuracy = -1
        hasGPSFix = false
        routePointCount = 0
        routeCoordinates = []
        currentCadence = 0
        currentRunningPower = 0
        currentStrideLength = 0
        currentVerticalOscillation = 0
        currentGroundContactTime = 0
        lastAltitude = nil
        laps = []
        currentLapDistance = 0
        currentLapSeconds = 0
        zoneSeconds = [0, 0, 0, 0, 0]
        isAutoPaused = false
        lapStartDistance = 0
        lapStartTime = 0
        lapStartAscent = 0
        lapHRSamples = []
        zoneLowerBounds = []
        lowSpeedSeconds = 0
        lastMetricDistance = 0
        paceStatus = .onTarget
        isActive = false
        isPaused = false
        isCountingDown = false
        countdownValue = 3
        countdownTimer?.invalidate()
        countdownTimer = nil
        hrSamples = []
        // NOTE: isShowingSummary + summary* are intentionally NOT reset here —
        // saveWorkout/discardWorkout set isShowingSummary=false themselves, and
        // the summary snapshot can stay until the next workout overwrites it.
    }
}

// MARK: - CLLocationManagerDelegate (GPS route + elevation)

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Filter to recent, accurate fixes (drop bad GPS points).
        let now = Date()
        let good = locations.filter {
            $0.horizontalAccuracy >= 0 &&
            $0.horizontalAccuracy <= 50 &&
            abs($0.timestamp.timeIntervalSince(now)) < 10
        }
        guard !good.isEmpty else { return }

        Task { @MainActor in
            // Feed the HealthKit route builder (this is what gets saved + exported).
            self.routeBuilder?.insertRouteData(good) { success, error in
                if let error = error {
                    print("insertRouteData error: \(error.localizedDescription)")
                }
                _ = success
            }

            for loc in good {
                // Elevation accumulation (only count meaningful deltas to cut noise).
                let alt = loc.altitude
                if let last = self.lastAltitude {
                    let delta = alt - last
                    if delta > 0.5 { self.totalAscent += delta }
                    else if delta < -0.5 { self.totalDescent += -delta }
                }
                self.lastAltitude = alt
                self.currentAltitude = alt
            }
            if let latest = good.last {
                self.gpsAccuracy = latest.horizontalAccuracy
                self.hasGPSFix = latest.horizontalAccuracy <= 20
            }
            self.routePointCount += good.count
            self.routeCoordinates.append(contentsOf: good.map { $0.coordinate })
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
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

                case HKQuantityType(.runningSpeed):
                    // m/s — refine current speed from the native running-speed channel
                    if let v = statistics?.mostRecentQuantity()?.doubleValue(for: HKUnit.meter().unitDivided(by: .second())) {
                        self.currentSpeed = v
                    }

                case HKQuantityType(.runningPower):
                    if let w = statistics?.mostRecentQuantity()?.doubleValue(for: .watt()) {
                        self.currentRunningPower = w
                    }

                case HKQuantityType(.runningStrideLength):
                    if let m = statistics?.mostRecentQuantity()?.doubleValue(for: .meter()) {
                        self.currentStrideLength = m
                    }

                case HKQuantityType(.runningVerticalOscillation):
                    if let cm = statistics?.mostRecentQuantity()?.doubleValue(for: HKUnit.meterUnit(with: .centi)) {
                        self.currentVerticalOscillation = cm
                    }

                case HKQuantityType(.runningGroundContactTime):
                    if let ms = statistics?.mostRecentQuantity()?.doubleValue(for: HKUnit.secondUnit(with: .milli)) {
                        self.currentGroundContactTime = ms
                    }

                case HKQuantityType(.stepCount):
                    // Cadence (spm): derive from step delta over elapsed time.
                    if let steps = statistics?.sumQuantity()?.doubleValue(for: .count()),
                       self.elapsedSeconds > 0 {
                        self.currentCadence = steps / (self.elapsedSeconds / 60.0)
                    }

                default:
                    break
                }
            }
        }
    }
}
#endif
