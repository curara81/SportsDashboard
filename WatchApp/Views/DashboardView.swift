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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerSection
                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else if let error = vm.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        readinessCard
                        trainingBalanceCard
                        acwrCard
                        hrvStatusCard
                        sleepCard
                        bodyCompositionCard
                        rhrCard
                        hrvChartCard
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 6)
            }
            .background(DS.pageBg)
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Status Badge

private struct StatusBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DS.badgeTextColor(for: label))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.badgeColor(for: label))
            .clipShape(Capsule())
    }
}

// MARK: - Card Container

struct CardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}
