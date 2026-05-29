import SwiftUI
import Charts

struct WeeklyTrendView: View {
    let loads: [DailyTrainingLoad]

    private var last7Days: [DayLoad] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let load = loads.first { cal.isDate($0.date, inSameDayAs: date) }
            return DayLoad(
                date: date,
                trimp: load?.trimp ?? 0,
                workoutType: load?.workoutType,
                tsb: load?.tsb ?? 0
            )
        }
    }

    private var weeklyTotal: Double { last7Days.map(\.trimp).reduce(0, +) }
    private var activeDays: Int { last7Days.filter { $0.trimp > 0 }.count }
    private var avgTRIMP: Double { activeDays > 0 ? weeklyTotal / Double(activeDays) : 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("주간 트렌드")
                    .font(.system(size: 17, weight: .bold))

                weekSummary
                trimpChart
                tsbChart
                monotonyCard
            }
            .padding(.horizontal, 6)
        }
    }

    private var weekSummary: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("주간 요약", systemImage: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                HStack(spacing: 0) {
                    summaryItem(label: "총 부하", value: "\(Int(weeklyTotal))")
                    Spacer()
                    summaryItem(label: "활동일", value: "\(activeDays)일")
                    Spacer()
                    summaryItem(label: "평균", value: "\(Int(avgTRIMP))")
                }
            }
        }
    }

    private var trimpChart: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("일별 부하 (TRIMP)", systemImage: "flame")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                Chart(last7Days) { day in
                    BarMark(
                        x: .value("날짜", day.date, unit: .day),
                        y: .value("TRIMP", day.trimp)
                    )
                    .foregroundStyle(barColor(day.trimp))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 70)
            }
        }
    }

    private var tsbChart: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("TSB 추이 (피로도)", systemImage: "waveform.path")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                Chart(last7Days) { day in
                    LineMark(x: .value("날짜", day.date), y: .value("TSB", day.tsb))
                        .foregroundStyle(day.tsb > 0 ? Color(red: 0.3, green: 0.85, blue: 0.45) : Color(red: 1.0, green: 0.65, blue: 0.2))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    AreaMark(x: .value("날짜", day.date), y: .value("TSB", day.tsb))
                        .foregroundStyle(
                            day.tsb > 0
                            ? Color(red: 0.3, green: 0.85, blue: 0.45).opacity(0.15)
                            : Color(red: 1.0, green: 0.65, blue: 0.2).opacity(0.15)
                        )
                    RuleMark(y: .value("Zero", 0))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                        .foregroundStyle(Color(white: 0.35))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 55)
            }
        }
    }

    private var monotonyCard: some View {
        let dailyLoads = last7Days.map(\.trimp)
        let result = MetricsEngine.calculateMonotonyStrain(dailyLoads: dailyLoads)

        return CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("단조로움 & 스트레인", systemImage: "chart.bar.doc.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                HStack(spacing: 0) {
                    summaryItem(label: "Monotony", value: String(format: "%.1f", result.monotony))
                    Spacer()
                    summaryItem(label: "Strain", value: "\(Int(result.strain))")
                    Spacer()
                    StatusBadge(label: result.monotonyRisk)
                }
            }
        }
    }

    private func summaryItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(Color(white: 0.55))
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded))
        }
    }

    private func barColor(_ trimp: Double) -> Color {
        switch trimp {
        case 150...: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case 100..<150: return Color(red: 1.0, green: 0.65, blue: 0.2)
        case 1...: return Color(red: 0.35, green: 0.65, blue: 1.0)
        default: return Color(white: 0.22)
        }
    }
}

private struct DayLoad: Identifiable {
    let id = UUID()
    let date: Date
    let trimp: Double
    let workoutType: String?
    let tsb: Double
}
