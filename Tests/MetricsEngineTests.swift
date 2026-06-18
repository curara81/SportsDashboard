import XCTest
import Foundation

// MetricsEngine + its model deps (DatedValue, DailyTrainingLoad) are compiled
// directly into this logic-test bundle (see project.yml), so they're referenced
// without an import. Tests cover the deterministic, public sports-science formulas.
final class MetricsEngineTests: XCTestCase {

    private let acc = 0.001

    // MARK: - CTL / ATL / TSB

    func testCTLATLFromZero() {
        let b = MetricsEngine.updateCTLATL(previousCTL: 0, previousATL: 0, todayLoad: 100)
        XCTAssertEqual(b.ctl, 100.0 / 42.0, accuracy: acc)   // ~2.381
        XCTAssertEqual(b.atl, 100.0 / 7.0, accuracy: acc)    // ~14.286
        XCTAssertEqual(b.tsb, b.ctl - b.atl, accuracy: acc)  // negative → fatigued
        XCTAssertEqual(b.label, "피로 누적")
    }

    func testTSBLabelFreshWhenPositive() {
        // Well rested: chronic fitness well above acute fatigue → large +TSB (>10).
        let b = MetricsEngine.updateCTLATL(previousCTL: 100, previousATL: 70, todayLoad: 0)
        XCTAssertGreaterThan(b.tsb, 10)
        XCTAssertEqual(b.label, "최상 컨디션")
    }

    // MARK: - ACWR (EWMA)

    func testACWRFromZero() {
        let r = MetricsEngine.updateACWR(previousAcute: 0, previousChronic: 0, todayLoad: 100)
        XCTAssertEqual(r.acute, 25.0, accuracy: acc)         // lambdaA = 2/8 = 0.25
        XCTAssertEqual(r.chronic, 200.0 / 29.0, accuracy: acc) // lambdaC = 2/29
        XCTAssertEqual(r.ratio, r.acute / r.chronic, accuracy: acc)
    }

    // MARK: - Heart Rate Recovery

    func testHRRRating() {
        let r = MetricsEngine.calculateHRR(peakHR: 170, hrAt60s: 140)
        XCTAssertEqual(r.value, 30, accuracy: acc)
        XCTAssertEqual(r.rating, "우수")
        XCTAssertEqual(MetricsEngine.calculateHRR(peakHR: 170, hrAt60s: 160).rating, "주의 필요")
    }

    // MARK: - Riegel race prediction

    func testRiegelPrediction() {
        // 5k in 20:00 → 10k via Riegel (exp 1.06)
        let t = MetricsEngine.predictRaceTime(knownDistance: 5000, knownTime: 1200, targetDistance: 10000)
        XCTAssertEqual(t, 1200 * pow(2, 1.06), accuracy: 0.01)
        XCTAssertGreaterThan(t, 2400) // worse than 2x linear, as expected
    }

    // MARK: - Session RPE

    func testSRPELoad() {
        XCTAssertEqual(MetricsEngine.calculateSRPELoad(rpe: 7, durationMinutes: 60), 420, accuracy: acc)
    }

    // MARK: - VO2max helpers

    func testVO2maxFromRunFlat() {
        // ACSM running: 0.2*speed + 3.5 (grade 0)
        XCTAssertEqual(MetricsEngine.estimateVO2maxFromRun(speedMetersPerMin: 200), 43.5, accuracy: acc)
    }

    func testSwainPercentVO2max() {
        XCTAssertEqual(MetricsEngine.swainPercentVO2maxFromPercentHRmax(percentHRmax: 90), (90 - 37) / 0.64, accuracy: acc)
    }

    // MARK: - Fitness age

    func testFitnessAgeClampsAndInterpolates() {
        // Above youngest male bracket (47.0 @ 20) → clamp to 20
        XCTAssertEqual(MetricsEngine.fitnessAge(vo2max: 50, actualAge: 40, isMale: true), 20)
        // Exactly the 44.0 bracket → age 30
        XCTAssertEqual(MetricsEngine.fitnessAge(vo2max: 44, actualAge: 40, isMale: true), 30)
        // Monotonic: fitter is never "older"
        let fit = MetricsEngine.fitnessAge(vo2max: 45, actualAge: 40, isMale: true)
        let unfit = MetricsEngine.fitnessAge(vo2max: 35, actualAge: 40, isMale: true)
        XCTAssertLessThanOrEqual(fit, unfit)
    }

    // MARK: - Monotony / Strain (FIX_NOTES regression: SD=0 cases)

    func testMonotonyUniformNonZeroWeekIsHighRisk() {
        // 7 identical non-zero days = perfectly monotonous = MAX risk (the old bug
        // scored this as safest). monotony must blow up, risk must be 위험.
        let m = MetricsEngine.calculateMonotonyStrain(dailyLoads: Array(repeating: 50, count: 7))
        XCTAssertGreaterThan(m.monotony, 100)
        XCTAssertEqual(m.monotonyRisk, "위험 (질병↑)")
        XCTAssertEqual(m.weeklyLoad, 350, accuracy: acc)
    }

    func testMonotonyAllRestWeekIsSafe() {
        let m = MetricsEngine.calculateMonotonyStrain(dailyLoads: Array(repeating: 0, count: 7))
        XCTAssertEqual(m.monotony, 0, accuracy: acc)
        XCTAssertEqual(m.monotonyRisk, "양호")
    }

    func testMonotonyInsufficientData() {
        let m = MetricsEngine.calculateMonotonyStrain(dailyLoads: [10, 20, 30])
        XCTAssertEqual(m.monotonyRisk, "데이터 부족")
    }

    // MARK: - Edwards / Banister TRIMP

    func testEdwardsTRIMPSingleZone5Interval() {
        let t0 = Date(timeIntervalSince1970: 0)
        let samples = [
            DatedValue(date: t0, value: 180),                              // 90% of 200 → weight 5
            DatedValue(date: t0.addingTimeInterval(60), value: 180),       // +1 min
        ]
        // 1 min * weight 5 = 5
        XCTAssertEqual(MetricsEngine.calculateEdwardsTRIMP(hrSamples: samples, maxHR: 200), 5, accuracy: acc)
    }

    func testBanisterTRIMPPositiveAndBounded() {
        let t0 = Date(timeIntervalSince1970: 0)
        let samples = [
            DatedValue(date: t0, value: 180),
            DatedValue(date: t0.addingTimeInterval(60), value: 180),
        ]
        let trimp = MetricsEngine.calculateTRIMP(hrSamples: samples, restingHR: 60, maxHR: 200, isMale: true)
        // hrr=0.857, 1min*0.857*0.64*exp(1.92*0.857) ≈ 2.84
        XCTAssertEqual(trimp, 2.84, accuracy: 0.1)
        // Below resting HR → zero
        XCTAssertEqual(MetricsEngine.calculateTRIMP(hrSamples: [], restingHR: 60, maxHR: 200, isMale: true), 0, accuracy: acc)
    }

    // MARK: - Training Effect

    func testTrainingEffectHighIntensityDominatesAnaerobic() {
        // 30 min in Z5 → anaerobic TE high and above aerobic
        let te = MetricsEngine.trainingEffect(zoneSeconds: [0, 0, 0, 0, 1800])
        XCTAssertGreaterThan(te.anaerobic, te.aerobic)
        XCTAssertGreaterThan(te.anaerobic, 4.0)
        XCTAssertLessThanOrEqual(te.anaerobic, 5.0)
    }

    func testTrainingEffectEmptyIsZero() {
        let te = MetricsEngine.trainingEffect(zoneSeconds: [0, 0, 0, 0, 0])
        XCTAssertEqual(te.aerobic, 0, accuracy: acc)
        XCTAssertEqual(te.anaerobic, 0, accuracy: acc)
        XCTAssertEqual(te.label, "효과 미미")
    }

    func testTrainingEffectWrongArityIsSafe() {
        let te = MetricsEngine.trainingEffect(zoneSeconds: [10, 20])
        XCTAssertEqual(te.label, "데이터 없음")
    }

    // MARK: - Cardio fitness level

    func testExpectedVO2maxInterpolates() {
        // Male age 35 sits between (30,44) and (40,41) → ~42.5
        XCTAssertEqual(MetricsEngine.expectedVO2max(age: 35, isMale: true), 42.5, accuracy: 0.01)
        // Clamps below youngest / above oldest bracket
        XCTAssertEqual(MetricsEngine.expectedVO2max(age: 18, isMale: true), 47, accuracy: 0.01)
        XCTAssertEqual(MetricsEngine.expectedVO2max(age: 90, isMale: false), 22, accuracy: 0.01)
    }

    func testCardioFitnessTiers() {
        // Well above age-norm → 최상위
        XCTAssertEqual(MetricsEngine.cardioFitnessLevel(vo2max: 60, age: 40, isMale: true).tier, "최상위")
        // At norm → 양호
        XCTAssertEqual(MetricsEngine.cardioFitnessLevel(vo2max: 41, age: 40, isMale: true).tier, "양호")
        // Far below → 매우 낮음
        XCTAssertEqual(MetricsEngine.cardioFitnessLevel(vo2max: 20, age: 40, isMale: true).tier, "매우 낮음")
        // No data
        XCTAssertEqual(MetricsEngine.cardioFitnessLevel(vo2max: 0, age: 40, isMale: true).tier, "--")
    }
}
