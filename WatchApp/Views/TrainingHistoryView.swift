import SwiftUI

struct TrainingHistoryView: View {
    let loads: [DailyTrainingLoad]

    private var recentWorkouts: [DailyTrainingLoad] {
        loads.filter { $0.trimp > 0 }.sorted { $0.date > $1.date }.prefix(10).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("운동 기록")
                    .font(.system(size: 17, weight: .bold))

                if recentWorkouts.isEmpty {
                    CardView {
                        Text("운동 기록 없음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(recentWorkouts, id: \.date) { load in
                        workoutRow(load)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func workoutRow(_ load: DailyTrainingLoad) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(load.workoutType ?? "운동")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(load.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.55))
                }

                HStack(spacing: 0) {
                    workoutMetric(label: "TRIMP", value: "\(Int(load.trimp))", color: trimpColor(load.trimp))
                    Spacer()
                    if let avg = load.avgHR {
                        workoutMetric(label: "평균HR", value: "\(Int(avg))", color: .white)
                    }
                    Spacer()
                    if let max = load.maxHR {
                        workoutMetric(label: "최대HR", value: "\(Int(max))", color: Color(red: 1.0, green: 0.35, blue: 0.35))
                    }
                    Spacer()
                    workoutMetric(label: "시간", value: "\(Int(load.durationMinutes))분", color: .white)
                }

                HStack(spacing: 8) {
                    miniLabel("CTL", value: "\(Int(load.ctl))", color: Color(red: 0.35, green: 0.65, blue: 1.0))
                    miniLabel("ATL", value: "\(Int(load.atl))", color: Color(red: 0.7, green: 0.45, blue: 1.0))
                    miniLabel("TSB", value: "\(Int(load.tsb))", color: load.tsb > 0
                              ? Color(red: 0.3, green: 0.85, blue: 0.45)
                              : Color(red: 1.0, green: 0.65, blue: 0.2))
                }
            }
        }
    }

    private func workoutMetric(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8)).foregroundStyle(Color(white: 0.55))
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
    }

    private func miniLabel(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(title).font(.system(size: 8)).foregroundStyle(color.opacity(0.7))
            Text(value).font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
        }
    }

    private func trimpColor(_ trimp: Double) -> Color {
        switch trimp {
        case 150...: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case 100..<150: return Color(red: 1.0, green: 0.65, blue: 0.2)
        default: return Color(red: 0.35, green: 0.65, blue: 1.0)
        }
    }
}
