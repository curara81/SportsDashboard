import SwiftUI
import SwiftData
import Charts

private enum DS {
    static let cardBg = Color(white: 0.12)
    static let pageBg = Color.black
    static let barBg = Color(white: 0.22)
    static let subtle = Color(white: 0.35)
    static let dimText = Color(white: 0.55)

    static let green = Color(red: 0.3, green: 0.85, blue: 0.45)
    static let orange = Color(red: 1.0, green: 0.65, blue: 0.2)
    static let red = Color(red: 1.0, green: 0.35, blue: 0.35)
    static let blue = Color(red: 0.35, green: 0.65, blue: 1.0)
    static let purple = Color(red: 0.7, green: 0.45, blue: 1.0)
    static let cyan = Color(red: 0.3, green: 0.8, blue: 0.85)

    static func readinessColor(_ score: Double) -> Color {
        switch score {
        case 80...: return green
        case 60..<80: return orange
        case 40..<60: return Color(red: 1.0, green: 0.5, blue: 0.2)
        default: return red
        }
    }

    static func badgeColor(for label: String) -> Color {
        switch label {
        case "우수", "최상 컨디션", "양호", "적정", "Balanced":
            return green.opacity(0.2)
        case "주의", "보통":
            return orange.opacity(0.2)
        default:
            return red.opacity(0.2)
        }
    }

    static func badgeTextColor(for label: String) -> Color {
        switch label {
        case "우수", "최상 컨디션", "양호", "적정", "Balanced":
            return green
        case "주의", "보통":
            return orange
        default:
            return red
        }
    }
}

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var currentDate = Date()
    #if os(watchOS)
    // App-session-scoped so an active workout survives navigating in/out of WorkoutStartView.
    @StateObject private var workoutManager = WorkoutManager()
    #endif

    var body: some View {
        NavigationStack {
            dashboardPages
                .background(DS.pageBg)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.dimText)
                        }
                    }
                }
                .task {
                    await vm.authorize()
                    await vm.loadMorningReport(context: modelContext)
                }
        }
    }

    /// Garmin-style one-metric-per-screen, Crown-paged (replaces the long scroll list).
    private var dashboardPages: some View {
        TabView {
            // Hub: start workout + today's activity
            ScrollView {
                VStack(spacing: 10) {
                    headerSection
                    #if os(watchOS)
                    workoutStartButton
                    #endif
                    dailyActivityCard
                }
                .padding(.horizontal, 6)
            }

            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.secondary).padding()
            } else {
                dashPage { readinessCard }
                dashPage { guidanceCard }
                NavigationLink { WeeklyTrendView(loads: vm.recentLoads) } label: { dashPage { trainingBalanceCard } }
                    .buttonStyle(.plain)
                dashPage { acwrCard }
                NavigationLink { HRZonesView(profile: vm.userProfile ?? UserProfile()) } label: { dashPage { hrvStatusCard } }
                    .buttonStyle(.plain)
                dashPage { trainingStatusCard }
                dashPage { vo2maxCard }
                dashPage { recoveryCard }
                dashPage { sleepCard }
                dashPage { sleepStagesCard }
                NavigationLink { TrainingHistoryView(loads: vm.recentLoads) } label: { dashPage { rhrCard } }
                    .buttonStyle(.plain)
                dashPage { hrvChartCard }
                dashPage { runningDynamicsCard }
                dashPage { loadFocusCard }
                dashPage { bodyCompositionCard }
                dashPage { quickLinks }
            }
        }
        #if os(watchOS)
        .tabViewStyle(.verticalPage)
        #endif
    }

    /// One dashboard card centered on its own page (scrolls if taller than the screen).
    private func dashPage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack { content() }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.top, 8)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(currentDate.formatted(.dateTime.month().day().weekday(.abbreviated)))
                .font(.system(size: 11))
                .foregroundStyle(DS.dimText)
            Text("모닝 리포트")
                .font(.system(size: 17, weight: .bold))
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Readiness

    private var readinessCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("훈련 준비도", systemImage: "heart.text.clipboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if let r = vm.readiness {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(r.score))")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.readinessColor(r.score))
                        Text("/ 100")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.dimText)
                        Spacer()
                        StatusBadge(label: r.label)
                    }

                    HStack(spacing: 0) {
                        subMetric(title: "수면", value: "\(String(format: "%.1f", vm.sleepHours ?? 0))h", score: r.sleepScore)
                        Spacer()
                        subMetric(title: "HRV", value: "\(Int(vm.latestHRV ?? 0))ms", score: r.hrvScore)
                        Spacer()
                        subMetric(title: "RHR", value: "\(Int(vm.restingHR ?? 0))", score: r.rhrScore)
                    }
                } else {
                    Text("데이터 부족").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - Training Balance (CTL/ATL/TSB)

    private var trainingBalanceCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("트레이닝 밸런스", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if let tb = vm.trainingBalance {
                    HStack(spacing: 0) {
                        metricPill(label: "CTL", value: "\(Int(tb.ctl))", color: DS.blue)
                        Spacer()
                        metricPill(label: "ATL", value: "\(Int(tb.atl))", color: DS.purple)
                        Spacer()
                        metricPill(label: "TSB", value: "\(Int(tb.tsb))", color: tb.tsb > 0 ? DS.green : DS.orange)
                        Spacer()
                        StatusBadge(label: tb.label)
                    }

                    if !vm.recentLoads.isEmpty {
                        Chart {
                            ForEach(vm.recentLoads.suffix(30), id: \.date) { load in
                                AreaMark(x: .value("날짜", load.date), y: .value("CTL", load.ctl))
                                    .foregroundStyle(DS.blue.opacity(0.15))
                                LineMark(x: .value("날짜", load.date), y: .value("CTL", load.ctl))
                                    .foregroundStyle(DS.blue.opacity(0.8))
                                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                                LineMark(x: .value("날짜", load.date), y: .value("ATL", load.atl))
                                    .foregroundStyle(DS.purple.opacity(0.6))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: true))
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 55)
                    }
                } else {
                    Text("운동 기록 없음").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - ACWR

    private var acwrCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("부상 위험 (ACWR)", systemImage: "exclamationmark.shield")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if vm.acwr > 0 {
                    HStack {
                        Text(String(format: "%.2f", vm.acwr))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(acwrColor(vm.acwr))
                        Spacer()
                        StatusBadge(label: vm.acwrLabel)
                    }

                    GeometryReader { geo in
                        let w = geo.size.width
                        let clamped = min(max(vm.acwr, 0), 2.0) / 2.0

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.barBg)
                                .frame(height: 8)

                            HStack(spacing: 0) {
                                Rectangle().fill(DS.orange.opacity(0.25))
                                    .frame(width: w * 0.4)
                                Rectangle().fill(DS.green.opacity(0.3))
                                    .frame(width: w * 0.25)
                                Rectangle().fill(DS.red.opacity(0.25))
                                    .frame(width: w * 0.35)
                            }
                            .frame(height: 8)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .offset(x: w * clamped - 6)
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text("부족").font(.system(size: 8)).foregroundStyle(DS.dimText)
                        Spacer()
                        Text("적정").font(.system(size: 8)).foregroundStyle(DS.green)
                        Spacer()
                        Text("위험").font(.system(size: 8)).foregroundStyle(DS.red)
                    }
                } else {
                    Text("운동 기록 필요").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - HRV Status

    private var hrvStatusCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("HRV 상태", systemImage: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if let s = vm.hrvStatus, s.status != .insufficientData {
                    HStack {
                        StatusBadge(label: s.status.rawValue)
                        Spacer()
                        Text("\(Int(s.sevenDayAverage))")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.cyan)
                        Text("ms")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.dimText)
                    }

                    GeometryReader { geo in
                        let w = geo.size.width
                        let range = s.upperBound - s.lowerBound
                        let clampedPos = min(max(s.sevenDayAverage, s.lowerBound), s.upperBound)
                        let fraction = range > 0 ? (clampedPos - s.lowerBound) / range : 0.5

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.barBg)
                                .frame(height: 8)

                            LinearGradient(
                                colors: [DS.red.opacity(0.4), DS.green.opacity(0.4), DS.red.opacity(0.4)],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(height: 8)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .offset(x: w * fraction - 6)
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text("Low").font(.system(size: 8)).foregroundStyle(DS.dimText)
                        Spacer()
                        Text("Baseline: \(Int(s.baseline))ms").font(.system(size: 8)).foregroundStyle(DS.dimText)
                        Spacer()
                        Text("High").font(.system(size: 8)).foregroundStyle(DS.dimText)
                    }
                } else {
                    Text("21일 이상 데이터 필요").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - Sleep

    private var sleepCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                Label("수면", systemImage: "moon.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if let hours = vm.sleepHours {
                    let h = Int(hours)
                    let m = Int((hours - Double(h)) * 60)
                    let pct = min(hours / 8.0, 1.0)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(h)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("시간 \(m)분")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.dimText)
                        Spacer()
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(sleepColor(pct))
                    }

                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.barBg)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(sleepColor(pct))
                                .frame(width: w * pct, height: 6)
                        }
                    }
                    .frame(height: 6)

                    if let d = vm.sleepDeep, let r = vm.sleepREM {
                        let sc = MetricsEngine.sleepScore(
                            asleepHours: hours, deepHours: d, remHours: r, awakeHours: vm.sleepAwake ?? 0)
                        let scColor: Color = sc.score >= 70 ? DS.green : (sc.score >= 55 ? DS.orange : DS.red)
                        HStack(spacing: 6) {
                            Text("수면 점수").font(.system(size: 9)).foregroundStyle(DS.dimText)
                            Text("\(sc.score)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(scColor)
                            Text(sc.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(scColor)
                        }
                    }

                    if let bank = vm.sleepBank {
                        HStack(spacing: 6) {
                            Text("수면 부채(7일)").font(.system(size: 9)).foregroundStyle(DS.dimText)
                            Text(String(format: "%@%.1fh", bank >= 0 ? "+" : "−", abs(bank)))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(bank >= 0 ? DS.green : DS.orange)
                        }
                    }
                } else {
                    Text("수면 데이터 없음").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - Body Composition

    private var bodyCompositionCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("체성분", systemImage: "figure.stand")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if let mass = vm.bodyMass {
                    HStack(spacing: 0) {
                        bodyMetric(label: "체중", value: String(format: "%.1f", mass), unit: "kg")
                        Spacer()
                        if let fat = vm.bodyFatPercentage {
                            bodyMetric(label: "체지방", value: String(format: "%.1f", fat), unit: "%")
                        }
                        Spacer()
                        if let lean = vm.leanBodyMass {
                            bodyMetric(label: "제지방", value: String(format: "%.1f", lean), unit: "kg")
                        }
                    }
                } else {
                    Text("체성분 데이터 없음").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - RHR

    private var rhrCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("안정시 심박수", systemImage: "heart.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.dimText)
                    Spacer()
                    if let rhr = vm.restingHR {
                        Text("\(Int(rhr))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("bpm")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.dimText)
                    }
                }

                if !HealthKitManager.shared.recentRHRValues.isEmpty {
                    Chart(HealthKitManager.shared.recentRHRValues) { item in
                        AreaMark(x: .value("날짜", item.date), y: .value("BPM", item.value))
                            .foregroundStyle(DS.red.opacity(0.1))
                        LineMark(x: .value("날짜", item.date), y: .value("BPM", item.value))
                            .foregroundStyle(DS.red.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        PointMark(x: .value("날짜", item.date), y: .value("BPM", item.value))
                            .foregroundStyle(DS.red.opacity(0.8))
                            .symbolSize(10)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 45)
                }
            }
        }
    }

    // MARK: - HRV Chart

    private var hrvChartCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("HRV 추이", systemImage: "waveform.path.ecg.rectangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.dimText)
                    Spacer()
                    if let hrv = vm.latestHRV {
                        Text("\(Int(hrv))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("ms")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.dimText)
                    }
                }

                if !HealthKitManager.shared.recentHRVValues.isEmpty {
                    Chart {
                        ForEach(HealthKitManager.shared.recentHRVValues) { item in
                            AreaMark(x: .value("날짜", item.date), y: .value("ms", item.value))
                                .foregroundStyle(DS.cyan.opacity(0.1))
                            LineMark(x: .value("날짜", item.date), y: .value("ms", item.value))
                                .foregroundStyle(DS.cyan.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        if let s = vm.hrvStatus, s.status != .insufficientData {
                            RuleMark(y: .value("Baseline", s.baseline))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .foregroundStyle(DS.dimText)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 55)
                }
            }
        }
    }

    // MARK: - Training Status

    private var trainingStatusCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                Label("트레이닝 상태", systemImage: "chart.bar.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                HStack {
                    Image(systemName: vm.trainingStatus.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(trainingStatusColor(vm.trainingStatus))
                    Text(vm.trainingStatus.rawValue)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(trainingStatusColor(vm.trainingStatus))
                    Spacer()
                    StatusBadge(label: trainingStatusBadge(vm.trainingStatus))
                }
            }
        }
    }

    // MARK: - Daily Guidance (Target Load + recommended run)

    private var guidanceCard: some View {
        let g = MetricsEngine.dailyGuidance(
            recentAvgLoad: vm.trainingBalance?.ctl ?? 0,
            readiness: vm.readiness?.score ?? 0,
            tsb: vm.trainingBalance?.tsb ?? 0)
        return CardView {
            VStack(alignment: .leading, spacing: 6) {
                Label("오늘의 추천", systemImage: "figure.run.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)
                Text(g.recommendation)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.green)
                Text("목표 부하 \(g.targetLoadLow)~\(g.targetLoadHigh)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("준비도 기반 · 오늘 적정 훈련량")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.dimText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - VO2max

    private var vo2maxCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                Label("VO2max", systemImage: "lungs.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if let vo2 = vm.vo2max {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.1f", vo2))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.cyan)
                        Text("ml/kg/min")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.dimText)
                        Spacer()
                        if let age = vm.fitnessAge {
                            VStack(spacing: 1) {
                                Text("피트니스 나이")
                                    .font(.system(size: 8))
                                    .foregroundStyle(DS.dimText)
                                Text("\(age)세")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(fitnessAgeColor(age, actual: vm.userProfile?.age ?? 30))
                            }
                        }
                    }
                    let cf = MetricsEngine.cardioFitnessLevel(
                        vo2max: vo2, age: vm.userProfile?.age ?? 30, isMale: vm.userProfile?.isMale ?? true)
                    HStack(spacing: 4) {
                        Text("심폐체력")
                            .font(.system(size: 9)).foregroundStyle(DS.dimText)
                        Text(cf.tier)
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(DS.green)
                        Text(cf.detail)
                            .font(.system(size: 8)).foregroundStyle(DS.dimText)
                    }
                } else {
                    Text("VO2max 데이터 없음")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - Sleep Stages

    private var sleepStagesCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("수면 단계", systemImage: "bed.double.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if let core = vm.sleepCore, let deep = vm.sleepDeep,
                   let rem = vm.sleepREM {
                    let total = core + deep + rem + (vm.sleepAwake ?? 0)

                    if total > 0 {
                        GeometryReader { geo in
                            let w = geo.size.width
                            HStack(spacing: 1) {
                                Rectangle()
                                    .fill(DS.blue)
                                    .frame(width: w * (core / total))
                                Rectangle()
                                    .fill(DS.purple)
                                    .frame(width: w * (deep / total))
                                Rectangle()
                                    .fill(DS.cyan)
                                    .frame(width: w * (rem / total))
                                if let awake = vm.sleepAwake, awake > 0 {
                                    Rectangle()
                                        .fill(DS.orange)
                                        .frame(width: w * (awake / total))
                                }
                            }
                            .frame(height: 10)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .frame(height: 10)

                        HStack(spacing: 0) {
                            sleepStageItem("코어", hours: core, color: DS.blue)
                            Spacer()
                            sleepStageItem("깊은", hours: deep, color: DS.purple)
                            Spacer()
                            sleepStageItem("REM", hours: rem, color: DS.cyan)
                            Spacer()
                            if let awake = vm.sleepAwake {
                                sleepStageItem("각성", hours: awake, color: DS.orange)
                            }
                        }
                    }
                } else {
                    Text("수면 단계 데이터 없음")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - Running Dynamics (summary card)

    private var runningDynamicsCard: some View {
        NavigationLink {
            RunningDynamicsView(
                power: vm.runningPower,
                cadence: vm.cadence,
                gct: vm.groundContactTime,
                verticalOsc: vm.verticalOscillation,
                strideLength: vm.strideLength
            )
        } label: {
            CardView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("러닝 다이내믹스", systemImage: "figure.run")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.dimText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.subtle)
                    }

                    if vm.runningPower != nil || vm.cadence != nil {
                        HStack(spacing: 0) {
                            if let p = vm.runningPower {
                                miniDynamic(label: "파워", value: "\(Int(p))W", color: DS.orange)
                            }
                            Spacer()
                            if let c = vm.cadence {
                                miniDynamic(label: "케이던스", value: "\(Int(c))", color: DS.blue)
                            }
                            Spacer()
                            if let g = vm.groundContactTime {
                                miniDynamic(label: "GCT", value: "\(Int(g))ms", color: DS.green)
                            }
                            Spacer()
                            if let s = vm.strideLength {
                                miniDynamic(label: "보폭", value: String(format: "%.2fm", s), color: DS.cyan)
                            }
                        }
                    } else {
                        Text("러닝 기록 필요")
                            .foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load Focus

    private var loadFocusCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("트레이닝 부하 분포", systemImage: "chart.pie.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if let focus = vm.loadFocus {
                    GeometryReader { geo in
                        let w = geo.size.width
                        HStack(spacing: 1) {
                            Rectangle()
                                .fill(DS.blue)
                                .frame(width: w * (focus.lowAerobic / 100))
                            Rectangle()
                                .fill(DS.orange)
                                .frame(width: w * (focus.highAerobic / 100))
                            Rectangle()
                                .fill(DS.red)
                                .frame(width: w * (focus.anaerobic / 100))
                        }
                        .frame(height: 10)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .frame(height: 10)

                    HStack(spacing: 0) {
                        focusItem("저강도", pct: focus.lowAerobic, color: DS.blue)
                        Spacer()
                        focusItem("고강도", pct: focus.highAerobic, color: DS.orange)
                        Spacer()
                        focusItem("무산소", pct: focus.anaerobic, color: DS.red)
                    }
                } else {
                    Text("부하 분포 데이터 없음")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - Recovery Time

    private var recoveryCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                Label("회복 시간", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)

                if let rt = vm.recoveryTime {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(rt.hours)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(recoveryColor(rt.hours))
                        Text("시간")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.dimText)
                        Spacer()
                        StatusBadge(label: rt.label)
                    }
                } else {
                    Text("운동 기록 필요")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - Daily Activity (today)

    private var dailyActivityCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("오늘의 활동", systemImage: "figure.walk.motion")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.dimText)
                HStack(spacing: 0) {
                    activityStat("걸음", vm.todaySteps.map { "\(Int($0))" } ?? "--", DS.green)
                    Spacer()
                    activityStat("거리", vm.todayDistanceKm.map { String(format: "%.1f", $0) } ?? "--", Color(red: 0.35, green: 0.65, blue: 1.0), unit: "km")
                    Spacer()
                    activityStat("칼로리", vm.todayActiveCalories.map { "\(Int($0))" } ?? "--", Color(red: 1.0, green: 0.65, blue: 0.2), unit: "kcal")
                    Spacer()
                    activityStat("운동", vm.todayExerciseMinutes.map { "\(Int($0))" } ?? "--", Color(red: 1.0, green: 0.4, blue: 0.4), unit: "분")
                }
            }
        }
    }

    private func activityStat(_ label: String, _ value: String, _ color: Color, unit: String = "") -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 8)).foregroundStyle(DS.dimText)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(color)
            if !unit.isEmpty { Text(unit).font(.system(size: 7)).foregroundStyle(DS.dimText) }
        }
    }

    // MARK: - Workout Start Button (top of dashboard — primary action)
    #if os(watchOS)
    private var workoutStartButton: some View {
        VStack(spacing: 6) {
            // Big primary "운동 시작" button
            NavigationLink {
                WorkoutStartView(manager: workoutManager)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 22, weight: .semibold))
                    Text("운동 시작")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(DS.green)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            // Quick-start chips per sport (skip countdown to picker)
            HStack(spacing: 6) {
                quickSportChip(.running, "figure.run", "러닝")
                quickSportChip(.walking, "figure.walk", "걷기")
                quickSportChip(.cycling, "figure.outdoor.cycle", "사이클")
            }
        }
    }

    private func quickSportChip(_ sport: WorkoutManager.SportType, _ icon: String, _ label: String) -> some View {
        NavigationLink {
            WorkoutStartView(manager: workoutManager, autoStart: sport)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: sport.color.r, green: sport.color.g, blue: sport.color.b))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.dimText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(white: 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Quick Links

    private var quickLinks: some View {
        VStack(spacing: 8) {
            NavigationLink {
                RacePredictionView()
            } label: {
                CardView {
                    HStack {
                        Image(systemName: "flag.checkered")
                            .foregroundStyle(DS.green)
                        Text("레이스 예측")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.dimText)
                    }
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                TrainingHistoryView(loads: vm.recentLoads)
            } label: {
                CardView {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                            .foregroundStyle(DS.blue)
                        Text("운동 기록")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.dimText)
                    }
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                ShoesView()
            } label: {
                CardView {
                    HStack {
                        Image(systemName: "shoe.2")
                            .foregroundStyle(DS.orange)
                        Text("신발")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.dimText)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Components

    private func subMetric(title: String, value: String, score: Double) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(DS.dimText)
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded))
            Text("\(Int(score))점")
                .font(.system(size: 9))
                .foregroundStyle(DS.readinessColor(score))
        }
    }

    private func metricPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(color.opacity(0.7))
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded))
        }
    }

    private func bodyMetric(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(DS.dimText)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(unit).font(.system(size: 9)).foregroundStyle(DS.dimText)
            }
        }
    }

    private func sleepStageItem(_ label: String, hours: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8)).foregroundStyle(color.opacity(0.7))
            Text(String(format: "%.1fh", hours))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func miniDynamic(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8)).foregroundStyle(DS.dimText)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func focusItem(_ label: String, pct: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8)).foregroundStyle(color.opacity(0.7))
            Text("\(Int(pct))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func trainingStatusColor(_ status: MetricsEngine.TrainingStatus) -> Color {
        switch status {
        case .peaking: return DS.green
        case .productive: return DS.blue
        case .maintaining: return DS.cyan
        case .recovery: return DS.purple
        case .unproductive: return DS.orange
        case .detraining: return Color(white: 0.55)
        case .overreaching: return DS.orange
        case .strained: return DS.red
        case .noStatus: return DS.dimText
        }
    }

    private func trainingStatusBadge(_ status: MetricsEngine.TrainingStatus) -> String {
        switch status {
        case .peaking, .productive: return "양호"
        case .maintaining, .recovery: return "보통"
        case .unproductive, .detraining: return "주의"
        case .overreaching, .strained: return "위험"
        case .noStatus: return "데이터 부족"
        }
    }

    private func fitnessAgeColor(_ fitnessAge: Int, actual: Int) -> Color {
        let diff = fitnessAge - actual
        if diff <= -5 { return DS.green }
        if diff <= 0 { return DS.blue }
        if diff <= 5 { return DS.orange }
        return DS.red
    }

    private func recoveryColor(_ hours: Int) -> Color {
        switch hours {
        case 0..<18: return DS.green
        case 18..<36: return DS.blue
        case 36..<60: return DS.orange
        default: return DS.red
        }
    }

    private func acwrColor(_ ratio: Double) -> Color {
        switch ratio {
        case 0.8..<1.3: return DS.green
        case 1.3..<1.5: return DS.orange
        case 1.5...: return DS.red
        default: return DS.orange
        }
    }

    private func sleepColor(_ pct: Double) -> Color {
        switch pct {
        case 0.875...: return DS.green
        case 0.75..<0.875: return DS.blue
        case 0.625..<0.75: return DS.orange
        default: return DS.red
        }
    }
}

// StatusBadge and CardView moved to Shared/Views/SharedComponents.swift
