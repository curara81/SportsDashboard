import Foundation

struct MetricsEngine {

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
        let twentyOneDayAgo = Calendar.current.date(byAdding: .day, value: -21, to: Date())!
        let sevenDayAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        let baselineValues = values.filter { $0.date >= twentyOneDayAgo }.map(\.value)
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
        let sevenDayAvg = recentValues.isEmpty ? mean : recentValues.reduce(0, +) / Double(recentValues.count)

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
            rhrScore = max(100.0 - (rhrDelta * 15.0), 0.0)
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
            let durationMin = hrSamples[i + 1].date.timeIntervalSince(hrSamples[i].date) / 60.0
            guard durationMin > 0 && durationMin < 5 else { continue }

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
            guard durationMin > 0 && durationMin < 5 else { continue }

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
            totalTRIMP += durationMin * weight
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

    // MARK: - Lucia TRIMP (3-zone ventilatory threshold)

    static func calculateLuciaTRIMP(
        hrSamples: [DatedValue],
        vt1HR: Double,
        vt2HR: Double
    ) -> Double {
        guard hrSamples.count >= 2 else { return 0 }

        var totalTRIMP = 0.0
        for i in 0..<(hrSamples.count - 1) {
            let hr = hrSamples[i].value
            let durationMin = hrSamples[i + 1].date.timeIntervalSince(hrSamples[i].date) / 60.0
            guard durationMin > 0 && durationMin < 5 else { continue }

            let weight: Double
            if hr >= vt2HR { weight = 3 }
            else if hr >= vt1HR { weight = 2 }
            else { weight = 1 }
            totalTRIMP += durationMin * weight
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

        let monotony = sd > 0 ? mean / sd : 0
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

    static func vo2maxFromSwain(percentHRmax: Double) -> Double {
        (percentHRmax - 37) / 0.64
    }

    // MARK: - Cardiac Drift

    static func calculateCardiacDrift(hrSamples: [DatedValue]) -> Double? {
        guard hrSamples.count >= 10 else { return nil }
        let mid = hrSamples.count / 2
        let firstHalf = hrSamples[..<mid].map(\.value)
        let secondHalf = hrSamples[mid...].map(\.value)

        let avgFirst = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let avgSecond = secondHalf.reduce(0, +) / Double(secondHalf.count)

        guard avgFirst > 0 else { return nil }
        return ((avgSecond - avgFirst) / avgFirst) * 100
    }

    // MARK: - Training Status (Garmin-style 8 levels)

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

        let vo2improving = (currentVO2max ?? 0) > (previousVO2max ?? 0)

        // Strained: very negative TSB + high load
        if currentTSB < -30 && recentAvgLoad > previousAvgLoad * 1.3 {
            return .strained
        }

        // Overreaching: negative TSB + increasing load but no fitness gain
        if currentTSB < -20 && ctlTrend > 2 && !vo2improving {
            return .overreaching
        }

        // Peaking: positive TSB + high CTL (taper phase)
        if currentTSB > 5 && recentCTL > 40 && recentAvgLoad < previousAvgLoad {
            return .peaking
        }

        // Recovery: very positive TSB, reduced load
        if currentTSB > 10 && recentAvgLoad < previousAvgLoad * 0.5 {
            return .recovery
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

        let totalHours = Int(baseHours * fatigueMultiplier * hrvMultiplier)

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

        // Find which age bracket the VO2max corresponds to
        for i in 0..<(norms.count - 1) {
            if vo2max >= norms[i].vo2max {
                return norms[i].age
            }
            if vo2max >= norms[i + 1].vo2max && vo2max < norms[i].vo2max {
                let fraction = (vo2max - norms[i + 1].vo2max) / (norms[i].vo2max - norms[i + 1].vo2max)
                return Int(Double(norms[i + 1].age) - fraction * Double(norms[i + 1].age - norms[i].age))
            }
        }

        return min(actualAge + 10, 80)
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
        guard hrSamples.count >= 2 else {
            return LoadFocus(lowAerobic: 0, highAerobic: 0, anaerobic: 0, dominantType: "데이터 없음")
        }

        var lowTime = 0.0
        var highTime = 0.0
        var anaerobicTime = 0.0

        for i in 0..<(hrSamples.count - 1) {
            let hr = hrSamples[i].value
            let dt = hrSamples[i + 1].date.timeIntervalSince(hrSamples[i].date) / 60.0
            guard dt > 0 && dt < 5 else { continue }

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
            case 0..<208: return "우수"
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
