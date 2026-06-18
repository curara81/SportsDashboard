import Foundation

struct MetricsEngine {

    // MARK: - [1] HRV Status (Section 2-1 of spec)
    // 21-day baseline → 7-day moving average → Balanced / Unbalanced

    struct HRVStatus {
        let baseline: Double        // 21-day mean (μ)
        let standardDeviation: Double // σ
        let lowerBound: Double      // μ - 1.5σ
        let upperBound: Double      // μ + 1.5σ
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
        // Baseline window DISJOINT from the 7-day comparison window (avoid self-contamination).
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

        guard !recentValues.isEmpty else {
            return HRVStatus(
                baseline: mean, standardDeviation: sd,
                lowerBound: lower, upperBound: upper,
                sevenDayAverage: 0, status: .insufficientData
            )
        }
        let sevenDayAvg = recentValues.reduce(0, +) / Double(recentValues.count)

        let status: HRVStatus.Status
        if sevenDayAvg < lower {
            status = .unbalancedLow
        } else if sevenDayAvg > upper {
            status = .unbalancedHigh
        } else {
            status = .balanced
        }

        return HRVStatus(
            baseline: mean,
            standardDeviation: sd,
            lowerBound: lower,
            upperBound: upper,
            sevenDayAverage: sevenDayAvg,
            status: status
        )
    }

    // MARK: - [2] Training Readiness (Section 2-2 of spec)
    // Score = (Sleep × 0.4) + (HRV × 0.4) + (RHR × 0.2)

    struct ReadinessResult {
        let score: Double           // 0-100
        let sleepScore: Double      // 0-100
        let hrvScore: Double        // 0-100
        let rhrScore: Double        // 0-100
        let label: String           // 우수 / 양호 / 주의 / 부족
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

        // Fail closed on NaN/Inf or bad divisor.
        guard sleepHours.isFinite, todayHRV.isFinite, hrvBaseline.isFinite,
              hrvLowerBound.isFinite, todayRHR.isFinite, rhrSevenDayAvg.isFinite,
              targetSleepHours.isFinite, targetSleepHours > 0 else {
            return ReadinessResult(score: 0, sleepScore: 0, hrvScore: 0, rhrScore: 0, label: "데이터 없음")
        }

        // S: Sleep score (% of target, capped at 100)
        let sleepScore = min((sleepHours / targetSleepHours) * 100.0, 100.0)

        // H: HRV score (linear interpolation between lower bound → baseline → 100)
        let hrvScore: Double
        if hrvLowerBound >= hrvBaseline {
            hrvScore = 50.0
        } else {
            let normalized = (todayHRV - hrvLowerBound) / (hrvBaseline - hrvLowerBound)
            hrvScore = min(max(normalized * 100.0, 0.0), 100.0)
        }

        // R: RHR score (lower than 7-day avg = good, 5+ BPM above = penalty)
        let rhrDelta = todayRHR - rhrSevenDayAvg
        let rhrScore: Double
        if rhrDelta <= 0 {
            rhrScore = 100.0
        } else if rhrDelta >= 5 {
            // Continue from 50 (value at delta=5) — no cliff (was 51→25 at delta 4.9→5.0).
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

        return ReadinessResult(
            score: total,
            sleepScore: sleepScore,
            hrvScore: hrvScore,
            rhrScore: rhrScore,
            label: label
        )
    }

    // MARK: - [3] TSB / CTL / ATL (Section: Suunto model)
    // TSB = CTL(42d EMA) - ATL(7d EMA)

    struct TrainingBalance {
        let ctl: Double     // Chronic Training Load (42-day)
        let atl: Double     // Acute Training Load (7-day)
        let tsb: Double     // Training Stress Balance (Form)
        let label: String   // 최상 / 보통 / 피로 누적
    }

    static func calculateTSB(dailyLoads: [DatedValue]) -> TrainingBalance {
        guard !dailyLoads.isEmpty else {
            return TrainingBalance(ctl: 0, atl: 0, tsb: 0, label: "데이터 없음")
        }

        let sorted = dailyLoads.sorted { $0.date < $1.date }

        // Exponential Moving Average
        let ctlDecay = 2.0 / (42.0 + 1.0)
        let atlDecay = 2.0 / (7.0 + 1.0)

        var ctl = sorted[0].value
        var atl = sorted[0].value

        for sample in sorted.dropFirst() {
            ctl = (sample.value - ctl) * ctlDecay + ctl
            atl = (sample.value - atl) * atlDecay + atl
        }

        let tsb = ctl - atl

        let label: String
        if tsb > 10 { label = "최상 컨디션" }
        else if tsb >= -10 { label = "보통" }
        else { label = "피로 누적" }

        return TrainingBalance(ctl: ctl, atl: atl, tsb: tsb, label: label)
    }
}
