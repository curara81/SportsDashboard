import SwiftUI
import HealthKit

/// Month calendar marking workout days (colored dot) and high-step days (green ring).
struct iOSCalendarView: View {
    @State private var monthAnchor = Calendar.current.startOfDay(for: Date())
    @State private var workoutDays: Set<Date> = []
    @State private var stepsByDay: [Date: Double] = [:]
    @State private var loading = true

    private let cal = Calendar.current
    private let stepGoal = 10000.0
    private let cols = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    weekdayHeader
                    grid
                    legend
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("캘린더")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthAnchor.formatted(.dateTime.year().month(.wide)))
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 4)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { d in
                Text(d).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(monthCells, id: \.self) { day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = cal.isDateInToday(day)
        let hasWorkout = workoutDays.contains(day)
        let bigStep = (stepsByDay[day] ?? 0) >= stepGoal
        return VStack(spacing: 3) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 14, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 28, height: 28)
                .background(isToday ? Circle().fill(.blue) : Circle().fill(.clear))
            HStack(spacing: 3) {
                Circle().fill(hasWorkout ? Color.green : .clear).frame(width: 6, height: 6)
                Circle().fill(bigStep ? Color.orange : .clear).frame(width: 6, height: 6)
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            label(.green, "운동")
            label(.orange, "1만보+")
            Spacer()
            if loading { ProgressView().scaleEffect(0.7) }
        }
        .font(.caption)
        .padding(.top, 4)
    }

    private func label(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).foregroundStyle(.secondary)
        }
    }

    // MARK: - Month grid cells (nil = padding before the 1st)

    private var monthCells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: monthAnchor),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor))
        else { return [] }
        let leading = cal.component(.weekday, from: first) - 1   // 0=Sun
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            if let date = cal.date(byAdding: .day, value: d - 1, to: first) {
                cells.append(cal.startOfDay(for: date))
            }
        }
        return cells
    }

    private func shiftMonth(_ by: Int) {
        if let m = cal.date(byAdding: .month, value: by, to: monthAnchor) {
            monthAnchor = m
            Task { await load() }
        }
    }

    private func load() async {
        loading = true
        let ws = (try? await HealthKitManager.shared.fetchWorkouts(daysBack: 400)) ?? []
        let days = Set(ws.map { cal.startOfDay(for: $0.startDate) })
        let steps = await HealthKitManager.shared.fetchDailySteps(daysBack: 400)
        await MainActor.run {
            self.workoutDays = days
            self.stepsByDay = steps
            self.loading = false
        }
    }
}
