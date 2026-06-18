import Foundation

struct MetricsEngine {

    /// Max minutes a single HR-sample interval can contribute to a load integral.
    /// Caps long gaps (pause / wrist-off / coarse sampling) instead of discarding
    /// them, so sparse data doesn't silently zero out a workout's load.
    static let maxIntervalMinutes: Double = 1.0

    // MARK: - HRV Status (21-day baseline)

    struct HRVStatus {
        let baseline: Double
        let standardDeviation: Double
        let lowerBound: Double
        let upperBound: Double
        let sevenDayAverage: Double
        let status: Status

        enum Status: String {
            case balanced = "Balanced"
            case unbalancedLow = "Unbalanced (Low)"
            case unbalancedHigh = "Unbalanced (High)"
            case insufficientData = "Insufficient Data"
        }
    }

    static func evaluateHRVStatus(values: [DatedValue]) -> HRVStatus {
        // Baseline window must be DISJOINT from the 7-day comparison window, else the
        // baseline is dragged toward the very average being tested (a sustained dip
        // raises its own lower bound and masks a real "unbalanced" state).
        let twentyEightDayAgo = Calendar.current.date(byAdding: .day, value: -28, to: Date())!
        let sevenDayAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        let baselineValues = values
            .filter { $0.date >= twentyEightDayAgo && $0.date < sevenDayAgo }
            .map(\.value)
        let recentValues = values.filter { $0.date >= sevenDayAgo }.map(\.value)

        guard baselineValues.count >= 5 else {
            return HRVStatus(
                baseline: 0, standardDeviation: 0,
                lowerBound: 0, upperBound: 0,
                sevenDayAverage: 0, status: .insufficientData
            )
        }

        let mean = baselineValues.reduce(0, +) / Double(baselineValues.count)
        let variance = baselineValues.map { pow($0 - mean, 2) }.reduce(0, +) / Double(baselineValues.count)
        let sd = sqrt(variance)
        let lower = mean - (1.5 * sd)
        let upper = mean + (1.5 * sd)

        // No recent data → don't fake "Balanced" from the baseline mean.
        guard !recentValues.isEmpty else {
            return HRVStatus(
                baseline: mean, standardDeviation: sd,
                lowerBound: lower, upperBound: upper,
                sevenDayAverage: 0, status: .insufficientData
            )
        }
        let sevenDayAvg = recentValues.reduce(0, +) / Double(recentValues.count)

        let status: HRVStatus.Status
        if sevenDayAvg < lower { status = .unbalancedLow }
        else if sevenDayAvg > upper { status = .unbalancedHigh }
        else { status = .balanced }

        return HRVStatus(baseline: mean, standardDeviation: sd,
                         lowerBound: lower, upperBound: upper,
                         sevenDayAverage: sevenDayAvg, status: status)
    }

    // MARK: - Training Readiness

    struct ReadinessResult {
        let score: Double
        let sleepScore: Double
        let hrvScore: Double
        let rhrScore: Double
        let label: String
    }

    static func calculateReadiness(
        sleepHours: Double,
        todayHRV: Double,
        hrvBaseline: Double,
        hrvLowerBound: Double,
        todayRHR: Double,
        rhrSevenDayAvg: Double,
        targetSleepHours: Double = 8.0
    ) -> ReadinessResult {
        // Fail closed on NaN/Inf or bad divisor — otherwise total becomes NaN and the
        // switch falls through to "부족" with a NaN score that the UI then renders.
        guard sleepHours.isFinite, todayHRV.isFinite, hrvBaseline.isFinite,
              hrvLowerBound.isFinite, todayRHR.isFinite, rhrSevenDayAvg.isFinite,
              targetSleepHours.isFinite, targetSleepHours > 0 else {
            return ReadinessResult(score: 0, sleepScore: 0, hrvScore: 0, rhrScore: 0, label: "데이터 없음")
        }
        let sleepScore = min((sleepHours / targetSleepHours) * 100.0, 100.0)

        let hrvScore: Double
        if hrvLowerBound >= hrvBaseline {
            hrvScore = 50.0
        } else {
            let normalized = (todayHRV - hrvLowerBound) / (hrvBaseline - hrvLowerBound)
            hrvScore = min(max(normalized * 100.0, 0.0), 100.0)
        }

        let rhrDelta = todayRHR - rhrSevenDayAvg
        let rhrScore: Double
        if rhrDelta <= 0 {
            rhrScore = 100.0
        } else if rhrDelta >= 5 {
            // Continue from 50 (the value at delta=5) instead of jumping to 25.
            // Old code cliff: delta 4.9→51 but 5.0→25 (a 0.1bpm change dropped 26pts).
            rhrScore = max(50.0 - (rhrDelta - 5.0) * 15.0, 0.0)
        } else {
            rhrScore = 100.0 - (rhrDelta * 10.0)
        }

        let total = (sleepScore * 0.4) + (hrvScore * 0.4) + (rhrScore * 0.2)

        let label: String
        switch total {
        case 80...: label = "우수"
        case 60..<80: label = "양호"
        case 40..<60: label = "주의"
        default: label = "부족"
        }

        return ReadinessResult(score: total, sleepScore: sleepScore,
                               hrvScore: hrvScore, rhrScore: rhrScore, label: label)
    }

    // MARK: - Banister TRIMP

    static func calculateTRIMP(
        hrSamples: [DatedValue],
        restingHR: Double,
        maxHR: Double,
        isMale: Bool
    ) -> Double {
        guard hrSamples.count >= 2, maxHR > restingHR else { return 0 }

        let k = isMale ? 0.64 : 0.86
        let y = isMale ? 1.92 : 1.67
        var totalTRIMP = 0.0

        for i in 0..<(hrSamples.count - 1) {
            let hr = hrSamples[i].value
            let rawDur = hrSamples[i + 1].date.timeIntervalSince(hrSamples[i].date) / 60.0
            guard rawDur > 0 else { continue }
            // Cap a single interval so a long gap (pause/wrist-off/sparse sampling)
            // doesn't count as continuous effort — but don't DISCARD it (that zeroed
            // out whole workouts on coarse data). See maxIntervalMinutes.
            let durationMin = min(rawDur, Self.maxIntervalMinutes)

            let hrr = (hr - restingHR) / (maxHR - restingHR)
            let clampedHRR = min(max(hrr, 0), 1)
            totalTRIMP += durationMin * clampedHRR * k * exp(y * clampedHRR)
        }

        return totalTRIMP
    }

    // MARK: - Edwards TRIMP (Zone-based)

    static func calculateEdwardsTRIMP(
        hrSamples: [DatedValue],
        maxHR: Double
    ) -> Double {
        guard hrSamples.count >= 2, maxHR > 0 else { return 0 }

        var totalTRIMP = 0.0

        for i in 0..<(hrSamples.count - 1) {
            let hr = hrSamples[i].value
            let durationMin = hrSamples[i + 1].date.timeIntervalSince(hrSamples[i].date) / 60.0
            guard durationMin > 0 else { continue }

            let pct = hr / maxHR * 100
            let weight: Double
            switch pct {
            case 90...: weight = 5
            case 80..<90: weight = 4
            case 70..<80: weight = 3
            case 60..<70: weight = 2
            case 50..<60: weight = 1
            default: weight = 0
            }
            totalTRIMP += min(durationMin, Self.maxIntervalMinutes) * weight
        }

        return totalTRIMP
    }

    // MARK: - CTL / ATL / TSB

    struct TrainingBalance {
        let ctl: Double
        let atl: Double
        let tsb: Double
        let label: String
    }

    static func updateCTLATL(previousCTL: Double, previousATL: Double, todayLoad: Double) -> TrainingBalance {
        let ctl = previousCTL + (todayLoad - previousCTL) / 42.0
        let atl = previousATL + (todayLoad - previousATL) / 7.0
        let tsb = ctl - atl

        let label: String
        if tsb > 10 { label = "최상 컨디션" }
        else if tsb >= -10 { label = "보통" }
        else { label = "피로 누적" }

        return TrainingBalance(ctl: ctl, atl: atl, tsb: tsb, label: label)
    }

    // MARK: - ACWR (EWMA method)

    static func updateACWR(
        previousAcute: Double,
        previousChronic: Double,
        todayLoad: Double
    ) -> (acute: Double, chronic: Double, ratio: Double) {
        let lambdaA = 2.0 / (7.0 + 1.0)
        let lambdaC = 2.0 / (28.0 + 1.0)

        let acute = todayLoad * lambdaA + (1 - lambdaA) * previousAcute
        let chronic = todayLoad * lambdaC + (1 - lambdaC) * previousChronic
        let ratio = chronic > 0 ? acute / chronic : 0

        return (acute, chronic, ratio)
    }

    static var acwrZone: (Double) -> String = { ratio in
        switch ratio {
        case 1.5...: return "위험"
        case 1.3..<1.5: return "주의"
        case 0.8..<1.3: return "적정"
        default: return "부족"
        }
    }

    // MARK: - Heart Rate Recovery

    static func calculateHRR(peakHR: Double, hrAt60s: Double) -> (value: Double, rating: String) {
        let hrr = peakHR - hrAt60s
        let rating: String
        switch hrr {
        case 30...: rating = "우수"
        case 23..<30: rating = "양호"
        case 18..<23: rating = "보통"
        case 12..<18: rating = "미흡"
        default: rating = "주의 필요"
        }
        return (hrr, rating)
    }

    // MARK: - Riegel Race Prediction

    static func predictRaceTime(
        knownDistance: Double,
        knownTime: TimeInterval,
        targetDistance: Double,
        fatigueExponent: Double = 1.06
    ) -> TimeInterval {
        knownTime * pow(targetDistance / knownDistance, fatigueExponent)
    }

    // MARK: - Daniels VDOT race prediction (VO2max-based)

    /// Predicts race time for a distance from VDOT (≈ running VO2max), via Daniels'
    /// VO2-demand vs sustainable-%VO2max model. Binary-searches the time where the
    /// VO2 cost of the average race velocity equals the VO2 sustainable for that time.
    static func vdotRaceTime(vdot: Double, distanceMeters: Double) -> TimeInterval {
        guard vdot > 0, distanceMeters > 0 else { return 0 }
        func vo2(_ vMetersPerMin: Double) -> Double {
            -4.60 + 0.182258 * vMetersPerMin + 0.000104 * vMetersPerMin * vMetersPerMin
        }
        func pctMax(_ tMin: Double) -> Double {
            0.8 + 0.1894393 * exp(-0.012778 * tMin) + 0.2989558 * exp(-0.1932605 * tMin)
        }
        var lo = 1.0, hi = 600.0   // minutes
        for _ in 0..<80 {
            let t = (lo + hi) / 2
            let v = distanceMeters / t   // m/min
            if vo2(v) > vdot * pctMax(t) { lo = t } else { hi = t }
            if hi - lo < 0.005 { break }
        }
        return (lo + hi) / 2 * 60.0   // seconds
    }

    // MARK: - Lucia TRIMP (3-zone ventilatory threshold)

    static func calculateLuciaTRIMP(
        hrSamples: [DatedValue],
        vt1HR: Double,
        vt2HR: Double
    ) -> Double {
        // Guard against unconfigured (0) or swapped/equal thresholds — without this,
        // vt2HR=0 makes every sample score weight 3 (max anaerobic), wildly inflating load.
        guard hrSamples.count >= 2, vt1HR > 0, vt2HR > vt1HR else { return 0 }

        var totalTRIMP = 0.0
        for i in 0..<(hrSamples.count - 1) {
            let hr = hrSamples[i].value
            let durationMin = hrSamples[i + 1].date.timeIntervalSince(hrSamples[i].date) / 60.0
            guard durationMin > 0 else { continue }

            let weight: Double
            if hr >= vt2HR { weight = 3 }
            else if hr >= vt1HR { weight = 2 }
            else { weight = 1 }
            totalTRIMP += min(durationMin, Self.maxIntervalMinutes) * weight
        }
        return totalTRIMP
    }

    // MARK: - Session RPE Training Load

    static func calculateSRPELoad(rpe: Double, durationMinutes: Double) -> Double {
        rpe * durationMinutes
    }

    // MARK: - Foster Training Monotony & Strain

    struct MonotonyStrain {
        let weeklyLoad: Double
        let monotony: Double
        let strain: Double
        let monotonyRisk: String
    }

    static func calculateMonotonyStrain(dailyLoads: [Double]) -> MonotonyStrain {
        guard dailyLoads.count >= 7 else {
            return MonotonyStrain(weeklyLoad: 0, monotony: 0, strain: 0, monotonyRisk: "데이터 부족")
        }

        let recent7 = Array(dailyLoads.suffix(7))
        let weeklyLoad = recent7.reduce(0, +)
        let mean = weeklyLoad / 7.0
        let variance = recent7.map { pow($0 - mean, 2) }.reduce(0, +) / 7.0
        let sd = sqrt(variance)

        // SD=0 has two opposite meanings:
        //  - uniform NON-ZERO week = maximum monotony (Foster mean/SD → ∞, highest risk)
        //  - all-zero rest week = no load, no risk
        // The old `sd>0 ? mean/sd : 0` scored the dangerous uniform week as safest (0).
        let monotony: Double
        if sd > 0 {
            monotony = mean / sd
        } else if mean > 0 {
            monotony = .greatestFiniteMagnitude   // perfectly uniform, non-zero → max monotony
        } else {
            monotony = 0                          // genuine full-rest week
        }
        let strain = weeklyLoad * monotony

        let risk: String
        if monotony > 2.0 { risk = "위험 (질병↑)" }
        else if monotony > 1.5 { risk = "주의" }
        else { risk = "양호" }

        return MonotonyStrain(weeklyLoad: weeklyLoad, monotony: monotony, strain: strain, monotonyRisk: risk)
    }

    // MARK: - VO2max Estimation

    static func estimateVO2maxFromRun(
        speedMetersPerMin: Double,
        grade: Double = 0
    ) -> Double {
        (0.2 * speedMetersPerMin) + (0.9 * speedMetersPerMin * grade) + 3.5
    }

    /// Swain (1994) regression: %VO2max = 0.64 * %HRmax - 37, rearranged.
    /// - Parameter percentHRmax: heart rate as a percentage of HRmax (e.g. 90 for 90%).
    /// - Returns: the corresponding **percentage of VO2max** (e.g. 82.8 means 82.8% of VO2max),
    ///   NOT an absolute VO2max in ml/kg/min. To get absolute VO2max, multiply by a known
    ///   reference: `result / 100 * knownVO2maxReference`.
    ///   Do NOT feed this value into `fitnessAge(vo2max:actualAge:isMale:)`, which expects ml/kg/min.
    static func swainPercentVO2maxFromPercentHRmax(percentHRmax: Double) -> Double {
        (percentHRmax - 37) / 0.64
    }

    // MARK: - Cardiac Drift

    static func calculateCardiacDrift(hrSamples: [DatedValue]) -> Double? {
        guard hrSamples.count >= 10 else { return nil }
        // Split by TIME, not sample index, and use a duration-weighted mean so irregular
        // sampling / gaps don't bias the result toward densely-sampled segments.
        let samples = hrSamples.sorted { $0.date < $1.date }
        let start = samples.first!.date
        let end = samples.last!.date
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return nil }
        let midTime = start.addingTimeInterval(total / 2)

        func weightedMean(_ lo: Date, _ hi: Date) -> Double? {
            var num = 0.0, den = 0.0
            for i in 0..<(samples.count - 1) {
                let segLo = max(samples[i].date, lo)
                let segHi = min(samples[i + 1].date, hi)
                let w = segHi.timeIntervalSince(segLo)
                if w > 0 { num += samples[i].value * w; den += w }
            }
            return den > 0 ? num / den : nil
        }

        guard let avgFirst = weightedMean(start, midTime),
              let avgSecond = weightedMean(midTime, end),
              avgFirst > 0 else { return nil }
        return ((avgSecond - avgFirst) / avgFirst) * 100
    }

    // MARK: - Training Status (8 levels)

    enum TrainingStatus: String {
        case peaking = "피킹"
        case productive = "생산적"
        case maintaining = "유지"
        case recovery = "회복"
        case unproductive = "비생산적"
        case detraining = "디트레이닝"
        case overreaching = "과부하"
        case strained = "과훈련"
        case noStatus = "데이터 부족"

        var icon: String {
            switch self {
            case .peaking: return "flame.fill"
            case .productive: return "arrow.up.right"
            case .maintaining: return "equal"
            case .recovery: return "bed.double.fill"
            case .unproductive: return "arrow.down.right"
            case .detraining: return "arrow.down"
            case .overreaching: return "exclamationmark.triangle"
            case .strained: return "xmark.octagon"
            case .noStatus: return "questionmark"
            }
        }
    }

    /// Determine training status based on CTL trend, TSB, and recent load pattern
    static func evaluateTrainingStatus(
        loads: [DailyTrainingLoad],
        currentVO2max: Double? = nil,
        previousVO2max: Double? = nil
    ) -> TrainingStatus {
        guard loads.count >= 14 else { return .noStatus }

        let recent7 = Array(loads.suffix(7))
        let previous7 = loads.count >= 14 ? Array(loads.suffix(14).prefix(7)) : []

        let recentCTL = recent7.last?.ctl ?? 0
        let previousCTL = previous7.last?.ctl ?? 0
        let ctlTrend = recentCTL - previousCTL
        let currentTSB = recent7.last?.tsb ?? 0

        let recentAvgLoad = recent7.map(\.trimp).reduce(0, +) / 7.0
        let previousAvgLoad = previous7.isEmpty ? recentAvgLoad : previous7.map(\.trimp).reduce(0, +) / 7.0

        // nil → "unknown" (don't coerce to 0, which made a single-sided value flip the result).
        let vo2KnownNotImproving: Bool = {
            guard let c = currentVO2max, let p = previousVO2max else { return false }
            return c <= p
        }()

        // Strained: very negative TSB + high load
        if currentTSB < -30 && recentAvgLoad > previousAvgLoad * 1.3 {
            return .strained
        }

        // Overreaching: negative TSB + increasing load + a MEASURED lack of fitness gain.
        if currentTSB < -20 && ctlTrend > 2 && vo2KnownNotImproving {
            return .overreaching
        }

        // Recovery: very positive TSB + deep load cut. Tested BEFORE Peaking, else any
        // fit athlete (CTL>40) on a recovery week was mislabeled "Peaking".
        if currentTSB > 10 && recentAvgLoad < previousAvgLoad * 0.5 {
            return .recovery
        }

        // Peaking: positive TSB + high CTL (genuine taper, not near-complete rest)
        if currentTSB > 5 && recentCTL > 40 && recentAvgLoad < previousAvgLoad {
            return .peaking
        }

        // Detraining: CTL dropping significantly
        if ctlTrend < -5 && recentAvgLoad < 20 {
            return .detraining
        }

        // Productive: CTL increasing + manageable TSB
        if ctlTrend > 1 && currentTSB > -25 {
            return .productive
        }

        // Unproductive: load present but CTL not increasing
        if recentAvgLoad > 30 && ctlTrend <= 0 {
            return .unproductive
        }

        // Maintaining: stable CTL
        return .maintaining
    }

    // MARK: - Recovery Time (hours)

    static func estimateRecoveryTime(
        lastTrimp: Double,
        currentTSB: Double,
        hrvStatus: HRVStatus?
    ) -> (hours: Int, label: String) {
        // Base recovery from workout intensity
        let baseHours: Double
        switch lastTrimp {
        case 200...: baseHours = 72
        case 150..<200: baseHours = 48
        case 100..<150: baseHours = 36
        case 60..<100: baseHours = 24
        case 30..<60: baseHours = 18
        default: baseHours = 12
        }

        // Adjust for fatigue (TSB)
        let fatigueMultiplier: Double
        if currentTSB < -20 { fatigueMultiplier = 1.5 }
        else if currentTSB < -10 { fatigueMultiplier = 1.25 }
        else if currentTSB > 10 { fatigueMultiplier = 0.75 }
        else { fatigueMultiplier = 1.0 }

        // Adjust for HRV status
        let hrvMultiplier: Double
        if let status = hrvStatus?.status {
            switch status {
            case .unbalancedLow: hrvMultiplier = 1.3
            case .unbalancedHigh: hrvMultiplier = 0.85
            case .balanced: hrvMultiplier = 1.0
            case .insufficientData: hrvMultiplier = 1.0
            }
        } else {
            hrvMultiplier = 1.0
        }

        let totalHours = Int((baseHours * fatigueMultiplier * hrvMultiplier).rounded())

        let label: String
        switch totalHours {
        case 0..<18: label = "가벼운 회복"
        case 18..<36: label = "하루 회복"
        case 36..<60: label = "충분한 휴식"
        default: label = "장기 회복 필요"
        }

        return (totalHours, label)
    }

    // MARK: - Fitness Age (from VO2max)

    static func fitnessAge(vo2max: Double, actualAge: Int, isMale: Bool) -> Int {
        // Normative VO2max values by age (mean values)
        // Based on ACSM percentile data
        let maleNorms: [(age: Int, vo2max: Double)] = [
            (20, 47.0), (25, 45.5), (30, 44.0), (35, 42.5),
            (40, 41.0), (45, 39.0), (50, 37.0), (55, 35.0),
            (60, 33.0), (65, 31.0), (70, 28.5), (75, 26.0)
        ]
        let femaleNorms: [(age: Int, vo2max: Double)] = [
            (20, 40.0), (25, 38.5), (30, 37.0), (35, 35.5),
            (40, 34.0), (45, 32.0), (50, 30.0), (55, 28.0),
            (60, 26.0), (65, 24.0), (70, 22.0), (75, 20.5)
        ]

        let norms = isMale ? maleNorms : femaleNorms

        // VO2max decreases with age, so norms are sorted by DESCENDING vo2max.
        // Clamp above the youngest bracket: very fit → cap at 20.
        if vo2max >= norms.first!.vo2max { return norms.first!.age }
        // Clamp below the oldest bracket.
        if vo2max <= norms.last!.vo2max { return norms.last!.age }

        // Linear interpolation between the two brackets that straddle vo2max.
        for i in 0..<(norms.count - 1) {
            let hi = norms[i]       // higher vo2max, younger age
            let lo = norms[i + 1]   // lower vo2max, older age
            if vo2max <= hi.vo2max && vo2max > lo.vo2max {
                let fraction = (vo2max - lo.vo2max) / (hi.vo2max - lo.vo2max) // 0..1
                let age = Double(lo.age) - fraction * Double(lo.age - hi.age)
                return Int(age.rounded())
            }
        }

        return min(actualAge + 10, 80)
    }

    // MARK: - Sleep Score (0–100 from HealthKit sleep)

    /// Composite 0–100 sleep score from HealthKit data (the same raw sleep AutoSleep
    /// writes). Weights: duration 45% + efficiency 25% + restoration 20% + HR-dip 10%.
    /// Efficiency prefers asleep/inBed (AutoSleep writes inBed); falls back to
    /// asleep/(asleep+awake). HR-dip term is dropped (weights renormalized) when
    /// sleeping/resting HR aren't available.
    static func sleepScore(asleepHours: Double, deepHours: Double, remHours: Double,
                           awakeHours: Double, inBedHours: Double? = nil,
                           sleepingHR: Double? = nil, restingHR: Double? = nil,
                           targetHours: Double = 8) -> (score: Int, label: String) {
        guard asleepHours > 0 else { return (0, "데이터 없음") }

        var parts: [(w: Double, v: Double)] = []

        // Duration vs need (45%)
        parts.append((0.45, min(asleepHours / targetHours, 1.0)))

        // Efficiency (25%): asleep/inBed if available, else asleep/(asleep+awake). 70%→0, 95%→1.
        let efficiency: Double
        if let ib = inBedHours, ib > 0 {
            efficiency = asleepHours / ib
        } else {
            efficiency = awakeHours > 0 ? asleepHours / (asleepHours + awakeHours) : 1.0
        }
        parts.append((0.25, min(max((efficiency - 0.70) / 0.25, 0), 1.0)))

        // Restoration (20%): deep+REM ≈ 40% of asleep is ideal.
        parts.append((0.20, min(((deepHours + remHours) / asleepHours) / 0.40, 1.0)))

        // HR dip (10%): sleeping HR ~15% below resting = full marks.
        if let shr = sleepingHR, let rhr = restingHR, rhr > 0 {
            parts.append((0.10, min(max(((rhr - shr) / rhr) / 0.15, 0), 1.0)))
        }

        let totalW = parts.reduce(0) { $0 + $1.w }
        let score = Int((parts.reduce(0) { $0 + $1.w * $1.v } / totalW * 100).rounded())
        let label: String
        switch score {
        case 85...: label = "매우 좋음"
        case 70..<85: label = "좋음"
        case 55..<70: label = "보통"
        case 40..<55: label = "부족"
        default: label = "나쁨"
        }
        return (score, label)
    }

    /// Sleep Bank (sleep debt): rolling sum of nightly (asleep − target), in hours.
    /// Negative = debt, positive = surplus. AutoSleep uses a ~7-night window.
    static func sleepBank(nightlyHours: [Double], targetHours: Double = 8) -> Double {
        nightlyHours.reduce(0) { $0 + ($1 - targetHours) }
    }

    // MARK: - Daily guidance (Target Load + recommended run)

    struct DailyGuidance {
        let targetLoadLow: Int
        let targetLoadHigh: Int
        let recommendation: String
        let detail: String
    }

    /// Today's target training-load band + a recommended session, from chronic load
    /// (recentAvgLoad ≈ CTL) scaled by readiness, plus a session pick from readiness/TSB.
    static func dailyGuidance(recentAvgLoad: Double, readiness: Double, tsb: Double) -> DailyGuidance {
        let rf = 0.5 + max(0, min(readiness, 100)) / 100.0   // 0.5 … 1.5
        let center = max(recentAvgLoad, 0) * rf
        let low = Int((center * 0.8).rounded())
        let high = Int((center * 1.2).rounded())
        let rec: String
        if readiness >= 80 && tsb > -5 { rec = "고강도 (인터벌·템포)" }
        else if readiness >= 60 { rec = "중강도 지속주" }
        else if readiness >= 40 { rec = "가벼운 회복 조깅" }
        else { rec = "휴식 권장" }
        return DailyGuidance(targetLoadLow: low, targetLoadHigh: high,
                             recommendation: rec,
                             detail: "준비도 \(Int(readiness)) · 목표 부하 \(low)~\(high)")
    }

    // MARK: - Cardio Fitness Level (VO2max → tier vs age/sex norm)

    /// Age/sex normative mean VO2max (≈50th percentile), interpolated.
    static func expectedVO2max(age: Int, isMale: Bool) -> Double {
        let male: [(Int, Double)] = [(20, 47), (30, 44), (40, 41), (50, 37), (60, 33), (70, 28.5)]
        let female: [(Int, Double)] = [(20, 40), (30, 37), (40, 34), (50, 30), (60, 26), (70, 22)]
        let norms = isMale ? male : female
        if age <= norms.first!.0 { return norms.first!.1 }
        if age >= norms.last!.0 { return norms.last!.1 }
        for i in 0..<(norms.count - 1) {
            let lo = norms[i], hi = norms[i + 1]
            if age >= lo.0 && age <= hi.0 {
                let f = Double(age - lo.0) / Double(hi.0 - lo.0)
                return lo.1 + (hi.1 - lo.1) * f
            }
        }
        return norms.last!.1
    }

    /// Maps VO2max to a 6-tier cardio-fitness label relative to the age/sex norm.
    static func cardioFitnessLevel(vo2max: Double, age: Int, isMale: Bool) -> (tier: String, detail: String) {
        let norm = expectedVO2max(age: age, isMale: isMale)
        guard norm > 0, vo2max > 0 else { return ("--", "데이터 부족") }
        let r = vo2max / norm
        let tier: String
        switch r {
        case 1.25...: tier = "최상위"
        case 1.10..<1.25: tier = "우수"
        case 0.95..<1.10: tier = "양호"
        case 0.85..<0.95: tier = "보통"
        case 0.70..<0.85: tier = "낮음"
        default: tier = "매우 낮음"
        }
        return (tier, "또래 평균 \(Int(norm.rounded())) 대비")
    }

    // MARK: - Training Effect (aerobic / anaerobic, 0.0–5.0)

    struct TrainingEffect {
        let aerobic: Double      // 0.0–5.0
        let anaerobic: Double    // 0.0–5.0
        let label: String        // benefit description
    }

    /// Approximate aerobic/anaerobic Training Effect from time-in-zone.
    /// Aerobic TE rises with total sustained Z2–Z4 time; anaerobic TE rises with
    /// Z4–Z5 (high-intensity) time. A heuristic proxy, not a validated lab measure.
    /// zoneSeconds: [Z1,Z2,Z3,Z4,Z5] seconds.
    static func trainingEffect(zoneSeconds: [TimeInterval]) -> TrainingEffect {
        guard zoneSeconds.count == 5 else {
            return TrainingEffect(aerobic: 0, anaerobic: 0, label: "데이터 없음")
        }
        let m = zoneSeconds.map { $0 / 60.0 }  // minutes per zone

        // Aerobic load: weighted minutes, saturating. Z2 builds base, Z3/Z4 build more.
        // Weights tuned so ~45min steady Z3 → ~3.0 ("유지/향상"), ~90min → ~4+.
        let aerobicWeighted = m[1] * 0.6 + m[2] * 1.0 + m[3] * 1.3 + m[4] * 0.8
        let aerobic = min(5.0, 5.0 * (1 - exp(-aerobicWeighted / 50.0)))

        // Anaerobic load: only high-intensity Z4/Z5 minutes, saturates faster.
        let anaerobicWeighted = m[3] * 0.7 + m[4] * 1.6
        let anaerobic = min(5.0, 5.0 * (1 - exp(-anaerobicWeighted / 12.0)))

        let label: String
        let peak = max(aerobic, anaerobic)
        switch peak {
        case 0..<1.0: label = "효과 미미"
        case 1.0..<2.0: label = "회복"
        case 2.0..<3.0: label = "유지"
        case 3.0..<4.0: label = "향상"
        case 4.0..<4.5: label = "큰 향상"
        default: label = "과부하"
        }
        return TrainingEffect(aerobic: aerobic, anaerobic: anaerobic, label: label)
    }

    // MARK: - Training Load Focus (Aerobic/Anaerobic distribution)

    struct LoadFocus {
        let lowAerobic: Double    // % time below VT1
        let highAerobic: Double   // % time VT1-VT2
        let anaerobic: Double     // % time above VT2
        let dominantType: String
    }

    static func calculateLoadFocus(
        hrSamples: [DatedValue],
        vt1HR: Double,
        vt2HR: Double
    ) -> LoadFocus {
        // Reject unconfigured (0) or swapped/equal thresholds (same bug class as Lucia).
        guard hrSamples.count >= 2, vt1HR > 0, vt2HR > vt1HR else {
            return LoadFocus(lowAerobic: 0, highAerobic: 0, anaerobic: 0, dominantType: "데이터 없음")
        }

        var lowTime = 0.0
        var highTime = 0.0
        var anaerobicTime = 0.0

        for i in 0..<(hrSamples.count - 1) {
            let hr = hrSamples[i].value
            let rawDt = hrSamples[i + 1].date.timeIntervalSince(hrSamples[i].date) / 60.0
            guard rawDt > 0 else { continue }
            let dt = min(rawDt, Self.maxIntervalMinutes)

            if hr >= vt2HR { anaerobicTime += dt }
            else if hr >= vt1HR { highTime += dt }
            else { lowTime += dt }
        }

        let total = lowTime + highTime + anaerobicTime
        guard total > 0 else {
            return LoadFocus(lowAerobic: 0, highAerobic: 0, anaerobic: 0, dominantType: "데이터 없음")
        }

        let lowPct = lowTime / total * 100
        let highPct = highTime / total * 100
        let anaerobicPct = anaerobicTime / total * 100

        let dominant: String
        if anaerobicPct > 40 { dominant = "무산소" }
        else if highPct > 40 { dominant = "고강도 유산소" }
        else { dominant = "저강도 유산소" }

        return LoadFocus(lowAerobic: lowPct, highAerobic: highPct, anaerobic: anaerobicPct, dominantType: dominant)
    }

    // MARK: - Running Dynamics Evaluation

    struct RunningDynamicsEval {
        let cadence: (value: Double, rating: String)?
        let groundContactTime: (value: Double, rating: String)?
        let verticalOscillation: (value: Double, rating: String)?
        let strideLength: (value: Double, rating: String)?

        static func rateCadence(_ spm: Double) -> String {
            switch spm {
            case 180...: return "우수"
            case 170..<180: return "양호"
            case 160..<170: return "보통"
            default: return "개선 필요"
            }
        }

        static func rateGCT(_ ms: Double) -> String {
            switch ms {
            case 150..<208: return "우수"   // <150ms is non-physiological → treat as bad/missing data
            case 208..<240: return "양호"
            case 240..<273: return "보통"
            default: return "개선 필요"
            }
        }

        static func rateVO(_ cm: Double) -> String {
            switch cm {
            case 0..<6.7: return "우수"
            case 6.7..<8.4: return "양호"
            case 8.4..<10.1: return "보통"
            default: return "개선 필요"
            }
        }

        static func rateStride(_ m: Double) -> String {
            switch m {
            case 1.2...: return "우수"
            case 1.0..<1.2: return "양호"
            case 0.8..<1.0: return "보통"
            default: return "짧음"
            }
        }
    }
}
