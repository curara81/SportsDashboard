import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @State private var currentDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = vm.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        readinessCard
                        hrvStatusCard
                        sleepCard
                        bodyCompositionCard
                        rhrCard
                        hrvChartCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGray6))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await vm.authorize()
                await vm.loadMorningReport()
            }
            .refreshable {
                await vm.loadMorningReport()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentDate.formatted(.dateTime.year().month().day().weekday(.wide)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("모닝 리포트")
                .font(.title2.weight(.semibold))
        }
    }

    // MARK: - Readiness

    private var readinessCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Label("훈련 준비도", systemImage: "heart.text.clipboard")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if let r = vm.readiness {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(r.score))")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("/ 100")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(r.label)
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(readinessColor(r.score).opacity(0.15))
                            .foregroundStyle(readinessColor(r.score))
                            .clipShape(Capsule())
                    }

                    Divider()

                    HStack(spacing: 0) {
                        subMetric(title: "수면", value: "\(String(format: "%.1f", vm.sleepHours ?? 0))h", score: r.sleepScore)
                        Spacer()
                        subMetric(title: "HRV", value: "\(Int(vm.latestHRV ?? 0)) ms", score: r.hrvScore)
                        Spacer()
                        subMetric(title: "안정시 심박", value: "\(Int(vm.restingHR ?? 0)) bpm", score: r.rhrScore)
                    }
                } else {
                    Text("데이터 부족")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - HRV Status

    private var hrvStatusCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Label("HRV 상태", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if let s = vm.hrvStatus, s.status != .insufficientData {
                    HStack {
                        Text(s.status.rawValue)
                            .font(.headline)
                        Spacer()
                        Text("\(Int(s.sevenDayAverage)) ms")
                            .font(.title3.weight(.semibold))
                    }

                    // Baseline range bar
                    GeometryReader { geo in
                        let width = geo.size.width
                        let range = s.upperBound - s.lowerBound
                        let clampedPos = min(max(s.sevenDayAverage, s.lowerBound), s.upperBound)
                        let fraction = range > 0 ? (clampedPos - s.lowerBound) / range : 0.5

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray4))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray2))
                                .frame(width: width * fraction, height: 8)

                            Circle()
                                .fill(Color.primary)
                                .frame(width: 14, height: 14)
                                .offset(x: width * fraction - 7)
                        }
                    }
                    .frame(height: 14)

                    HStack {
                        Text("\(Int(s.lowerBound)) ms")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("정상 범위")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(s.upperBound)) ms")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("21일 이상 데이터 필요")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Sleep

    private var sleepCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("수면", systemImage: "moon.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if let hours = vm.sleepHours {
                    let h = Int(hours)
                    let m = Int((hours - Double(h)) * 60)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(h)시간 \(m)분")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("목표 8시간 대비 \(Int(min(hours / 8.0 * 100, 100)))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: min(hours / 8.0, 1.0))
                        .tint(Color(.systemGray))
                } else {
                    Text("수면 데이터 없음").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Body Composition

    private var bodyCompositionCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("체성분", systemImage: "figure.stand")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if let mass = vm.bodyMass {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("체중")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f kg", mass))
                                .font(.title3.weight(.semibold))
                        }
                        Spacer()
                        if let fat = vm.bodyFatPercentage {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("체지방")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f%%", fat))
                                    .font(.title3.weight(.semibold))
                            }
                        }
                        Spacer()
                        if let lean = vm.leanBodyMass {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("제지방")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f kg", lean))
                                    .font(.title3.weight(.semibold))
                            }
                        }
                    }

                    if !HealthKitManager.shared.recentBodyMassValues.isEmpty {
                        Chart {
                            ForEach(HealthKitManager.shared.recentBodyMassValues) { item in
                                LineMark(
                                    x: .value("날짜", item.date),
                                    y: .value("kg", item.value)
                                )
                                .foregroundStyle(Color(.systemGray))
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis {
                            AxisMarks(values: .automatic) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.month().day())
                            }
                        }
                        .frame(height: 100)
                    }
                } else {
                    Text("체성분 데이터 없음").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - RHR

    private var rhrCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("안정시 심박수 (7일)", systemImage: "heart.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if !HealthKitManager.shared.recentRHRValues.isEmpty {
                    Chart(HealthKitManager.shared.recentRHRValues) { item in
                        LineMark(
                            x: .value("날짜", item.date),
                            y: .value("BPM", item.value)
                        )
                        .foregroundStyle(Color(.systemGray))
                        PointMark(
                            x: .value("날짜", item.date),
                            y: .value("BPM", item.value)
                        )
                        .foregroundStyle(Color.primary)
                        .symbolSize(20)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    // MARK: - HRV Chart

    private var hrvChartCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("HRV 추이 (21일)", systemImage: "waveform.path.ecg.rectangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if !HealthKitManager.shared.recentHRVValues.isEmpty {
                    Chart {
                        ForEach(HealthKitManager.shared.recentHRVValues) { item in
                            LineMark(
                                x: .value("날짜", item.date),
                                y: .value("ms", item.value)
                            )
                            .foregroundStyle(Color(.systemGray))
                        }

                        if let s = vm.hrvStatus, s.status != .insufficientData {
                            RuleMark(y: .value("Baseline", s.baseline))
                                .lineStyle(StrokeStyle(dash: [5, 3]))
                                .foregroundStyle(Color(.systemGray3))

                            RectangleMark(
                                yStart: .value("Lower", s.lowerBound),
                                yEnd: .value("Upper", s.upperBound)
                            )
                            .foregroundStyle(Color(.systemGray5).opacity(0.5))
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .frame(height: 160)
                }
            }
        }
    }

    // MARK: - Components

    private func subMetric(title: String, value: String, score: Double) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
            Text("\(Int(score))점")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func readinessColor(_ score: Double) -> Color {
        switch score {
        case 80...: return .primary
        case 60..<80: return Color(.systemGray)
        case 40..<60: return Color(.systemGray2)
        default: return Color(.systemGray3)
        }
    }
}

// MARK: - Card Container

struct CardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

#Preview {
    DashboardView()
}
