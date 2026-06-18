import SwiftUI
import SwiftData
import Charts

struct iOSDashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var currentDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    if vm.isLoading {
                        ProgressView("데이터 로드 중...")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = vm.errorMessage {
                        Text(error).foregroundStyle(.secondary).padding()
                    } else {
                        readinessSection
                        trainingSection
                        healthSection
                        bodySection
                        quickLinksSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SportsDashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        iOSSettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .task {
                await vm.authorize()
                await vm.loadMorningReport(context: modelContext)
            }
            .refreshable {
                await vm.loadMorningReport(context: modelContext)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentDate.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("모닝 리포트")
                    .font(.largeTitle.bold())
            }
            Spacer()
        }
    }

    // MARK: - Readiness

    private var readinessSection: some View {
        VStack(spacing: 12) {
            if let r = vm.readiness {
                HStack(spacing: 16) {
                    // Readiness Score
                    iOSCard {
                        VStack(spacing: 8) {
                            Text("훈련 준비도")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ZStack {
                                Circle()
                                    .stroke(Color(.systemGray5), lineWidth: 8)
                                    .frame(width: 100, height: 100)
                                Circle()
                                    .trim(from: 0, to: r.score / 100)
                                    .stroke(readinessColor(r.score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .frame(width: 100, height: 100)
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 0) {
                                    Text("\(Int(r.score))")
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                    Text(r.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Sub scores
                    VStack(spacing: 8) {
                        scoreRow(icon: "moon.fill", title: "수면", value: String(format: "%.1fh", vm.sleepHours ?? 0), score: r.sleepScore, color: .blue)
                        scoreRow(icon: "waveform.path.ecg", title: "HRV", value: "\(Int(vm.latestHRV ?? 0))ms", score: r.hrvScore, color: .cyan)
                        scoreRow(icon: "heart.fill", title: "RHR", value: "\(Int(vm.restingHR ?? 0))bpm", score: r.rhrScore, color: .red)
                    }
                }
            }

            // Training Status + VO2max
            HStack(spacing: 12) {
                iOSCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("트레이닝 상태", systemImage: vm.trainingStatus.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(vm.trainingStatus.rawValue)
                            .font(.title2.bold())
                            .foregroundStyle(trainingStatusColor(vm.trainingStatus))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                iOSCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("VO2max", systemImage: "lungs.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let vo2 = vm.vo2max {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", vo2))
                                    .font(.title2.bold())
                                    .foregroundStyle(.cyan)
                                Text("ml/kg/min")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let age = vm.fitnessAge {
                                Text("피트니스 나이 \(age)세")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("--").font(.title2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Training

    private var trainingSection: some View {
        VStack(spacing: 12) {
            // CTL/ATL/TSB
            if let tb = vm.trainingBalance {
                iOSCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("트레이닝 밸런스", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 20) {
                            metricColumn("CTL", value: "\(Int(tb.ctl))", color: .blue)
                            metricColumn("ATL", value: "\(Int(tb.atl))", color: .purple)
                            metricColumn("TSB", value: "\(Int(tb.tsb))", color: tb.tsb > 0 ? .green : .orange)
                            Spacer()
                            StatusBadge(label: tb.label)
                        }

                        if !vm.recentLoads.isEmpty {
                            Chart {
                                ForEach(vm.recentLoads.suffix(30), id: \.date) { load in
                                    AreaMark(x: .value("", load.date), y: .value("CTL", load.ctl))
                                        .foregroundStyle(.blue.opacity(0.1))
                                    LineMark(x: .value("", load.date), y: .value("CTL", load.ctl))
                                        .foregroundStyle(.blue)
                                        .lineStyle(StrokeStyle(lineWidth: 2))
                                    LineMark(x: .value("", load.date), y: .value("ATL", load.atl))
                                        .foregroundStyle(.purple.opacity(0.6))
                                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                }
                            }
                            .chartYScale(domain: .automatic(includesZero: true))
                            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine() } }
                            .chartYAxis { AxisMarks(position: .leading) }
                            .frame(height: 120)
                        }
                    }
                }
            }

            // ACWR + Recovery
            HStack(spacing: 12) {
                iOSCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("ACWR", systemImage: "exclamationmark.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", vm.acwr))
                            .font(.title.bold())
                            .foregroundStyle(acwrColor(vm.acwr))
                        StatusBadge(label: vm.acwrLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                iOSCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("회복 시간", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let rt = vm.recoveryTime {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(rt.hours)")
                                    .font(.title.bold())
                                    .foregroundStyle(recoveryColor(rt.hours))
                                Text("시간")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            StatusBadge(label: rt.label)
                        } else {
                            Text("--").font(.title).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Load Focus
            if let focus = vm.loadFocus {
                iOSCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("트레이닝 부하 분포", systemImage: "chart.pie.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.blue)
                                    .frame(width: geo.size.width * focus.lowAerobic / 100)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.orange)
                                    .frame(width: geo.size.width * focus.highAerobic / 100)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.red)
                                    .frame(width: geo.size.width * focus.anaerobic / 100)
                            }
                        }
                        .frame(height: 16)

                        HStack {
                            focusLabel("저강도", pct: focus.lowAerobic, color: .blue)
                            Spacer()
                            focusLabel("고강도", pct: focus.highAerobic, color: .orange)
                            Spacer()
                            focusLabel("무산소", pct: focus.anaerobic, color: .red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Health

    private var healthSection: some View {
        VStack(spacing: 12) {
            // Sleep + Sleep Stages
            iOSCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("수면", systemImage: "moon.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let hours = vm.sleepHours {
                        HStack {
                            Text(String(format: "%.1f시간", hours))
                                .font(.title2.bold())
                            Spacer()
                            if let d = vm.sleepDeep, let r = vm.sleepREM {
                                let sc = MetricsEngine.sleepScore(
                                    asleepHours: hours, deepHours: d, remHours: r, awakeHours: vm.sleepAwake ?? 0,
                                    inBedHours: vm.sleepInBedHours, sleepingHR: vm.sleepingHR, restingHR: vm.restingHR)
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text("\(sc.score)점")
                                        .font(.headline.bold())
                                        .foregroundStyle(sc.score >= 70 ? .green : sc.score >= 55 ? .orange : .red)
                                    Text(sc.label).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let bank = vm.sleepBank {
                            HStack {
                                Text("수면 부채(7일)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%@%.1fh", bank >= 0 ? "+" : "−", abs(bank)))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(bank >= 0 ? .green : .orange)
                            }
                        }

                        if let core = vm.sleepCore, let deep = vm.sleepDeep, let rem = vm.sleepREM {
                            let total = core + deep + rem + (vm.sleepAwake ?? 0)
                            if total > 0 {
                                GeometryReader { geo in
                                    HStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 4).fill(.blue)
                                            .frame(width: geo.size.width * core / total)
                                        RoundedRectangle(cornerRadius: 4).fill(.purple)
                                            .frame(width: geo.size.width * deep / total)
                                        RoundedRectangle(cornerRadius: 4).fill(.cyan)
                                            .frame(width: geo.size.width * rem / total)
                                        if let a = vm.sleepAwake, a > 0 {
                                            RoundedRectangle(cornerRadius: 4).fill(.orange)
                                                .frame(width: geo.size.width * a / total)
                                        }
                                    }
                                }
                                .frame(height: 12)

                                HStack {
                                    sleepLabel("코어", h: core, color: .blue)
                                    Spacer()
                                    sleepLabel("깊은", h: deep, color: .purple)
                                    Spacer()
                                    sleepLabel("REM", h: rem, color: .cyan)
                                    Spacer()
                                    if let a = vm.sleepAwake {
                                        sleepLabel("각성", h: a, color: .orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // HRV + RHR Charts
            HStack(spacing: 12) {
                iOSCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("HRV", systemImage: "waveform.path.ecg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let hrv = vm.latestHRV {
                                Text("\(Int(hrv))ms")
                                    .font(.headline.bold())
                                    .foregroundStyle(.cyan)
                            }
                        }
                        if !HealthKitManager.shared.recentHRVValues.isEmpty {
                            Chart(HealthKitManager.shared.recentHRVValues) { item in
                                LineMark(x: .value("", item.date), y: .value("ms", item.value))
                                    .foregroundStyle(.cyan)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .frame(height: 60)
                        }
                    }
                }

                iOSCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("RHR", systemImage: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let rhr = vm.restingHR {
                                Text("\(Int(rhr))bpm")
                                    .font(.headline.bold())
                                    .foregroundStyle(.red)
                            }
                        }
                        if !HealthKitManager.shared.recentRHRValues.isEmpty {
                            Chart(HealthKitManager.shared.recentRHRValues) { item in
                                LineMark(x: .value("", item.date), y: .value("bpm", item.value))
                                    .foregroundStyle(.red)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .frame(height: 60)
                        }
                    }
                }
            }

            // Running Dynamics
            if vm.runningPower != nil || vm.cadence != nil {
                iOSCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("러닝 다이내믹스", systemImage: "figure.run")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            if let p = vm.runningPower { dynamicItem("파워", "\(Int(p))W", .orange) }
                            if let c = vm.cadence { dynamicItem("케이던스", "\(Int(c))spm", .blue) }
                            if let g = vm.groundContactTime { dynamicItem("GCT", "\(Int(g))ms", .green) }
                            if let s = vm.strideLength { dynamicItem("보폭", String(format: "%.2fm", s), .cyan) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Body

    private var bodySection: some View {
        Group {
            if vm.bodyMass != nil {
                iOSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("체성분", systemImage: "figure.stand")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 20) {
                            if let m = vm.bodyMass { metricColumn("체중", value: String(format: "%.1fkg", m), color: .primary) }
                            if let f = vm.bodyFatPercentage { metricColumn("체지방", value: String(format: "%.1f%%", f), color: .orange) }
                            if let l = vm.leanBodyMass { metricColumn("제지방", value: String(format: "%.1fkg", l), color: .blue) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quick Links

    private var quickLinksSection: some View {
        VStack(spacing: 8) {
            NavigationLink {
                RacePredictionView()
            } label: {
                iOSLinkRow(icon: "flag.checkered", title: "레이스 예측", color: .green)
            }
            NavigationLink {
                TrainingHistoryView(loads: vm.recentLoads)
            } label: {
                iOSLinkRow(icon: "list.bullet.clipboard", title: "운동 기록", color: .blue)
            }
            NavigationLink {
                HRZonesView(profile: vm.userProfile ?? UserProfile())
            } label: {
                iOSLinkRow(icon: "heart.text.clipboard", title: "HR 존", color: .red)
            }
            NavigationLink {
                WeeklyTrendView(loads: vm.recentLoads)
            } label: {
                iOSLinkRow(icon: "chart.bar.fill", title: "주간 트렌드", color: .purple)
            }
        }
    }

    // MARK: - Components

    private func scoreRow(icon: String, title: String, value: String, score: Double, color: Color) -> some View {
        iOSCard {
            HStack {
                Image(systemName: icon).foregroundStyle(color).frame(width: 20)
                Text(title).font(.caption)
                Spacer()
                Text(value).font(.subheadline.bold())
                Text("\(Int(score))점")
                    .font(.caption2)
                    .foregroundStyle(readinessColor(score))
            }
        }
    }

    private func metricColumn(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.bold()).foregroundStyle(color)
        }
    }

    private func focusLabel(_ title: String, pct: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(color)
            Text("\(Int(pct))%").font(.caption.bold()).foregroundStyle(color)
        }
    }

    private func sleepLabel(_ title: String, h: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(color)
            Text(String(format: "%.1fh", h)).font(.caption.bold()).foregroundStyle(color)
        }
    }

    private func dynamicItem(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).foregroundStyle(color)
        }
    }

    private func iOSLinkRow(icon: String, title: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Colors

    private func readinessColor(_ score: Double) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    private func trainingStatusColor(_ status: MetricsEngine.TrainingStatus) -> Color {
        switch status {
        case .peaking: return .green
        case .productive: return .blue
        case .maintaining: return .cyan
        case .recovery: return .purple
        case .unproductive, .overreaching: return .orange
        case .detraining: return .gray
        case .strained: return .red
        case .noStatus: return .secondary
        }
    }

    private func acwrColor(_ ratio: Double) -> Color {
        switch ratio {
        case 0.8..<1.3: return .green
        case 1.3..<1.5: return .orange
        case 1.5...: return .red
        default: return .orange
        }
    }

    private func recoveryColor(_ hours: Int) -> Color {
        switch hours {
        case 0..<18: return .green
        case 18..<36: return .blue
        case 36..<60: return .orange
        default: return .red
        }
    }
}

// MARK: - iOS Card

struct iOSCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
