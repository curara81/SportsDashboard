import SwiftUI
import CoreLocation
import HealthKit

/// Lists actual HealthKit workouts (what Apple Fitness shows), newest first, so a
/// just-saved run always appears — independent of the daily training-load pipeline.
struct TrainingHistoryView: View {
    var loads: [DailyTrainingLoad] = []   // kept for call-site compatibility (unused here)

    @State private var workouts: [HKWorkout] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("운동 기록")
                    .font(.system(size: 17, weight: .bold))

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else if workouts.isEmpty {
                    CardView {
                        Text("운동 기록 없음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(workouts, id: \.uuid) { w in
                        NavigationLink {
                            WorkoutDetailView(workout: w)
                        } label: {
                            workoutRow(w)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .onAppear(perform: load)
    }

    private func load() {
        Task {
            let ws = (try? await HealthKitManager.shared.fetchWorkouts(daysBack: 60)) ?? []
            await MainActor.run {
                self.workouts = ws.sorted { $0.startDate > $1.startDate }
                self.loading = false
            }
        }
    }

    private func workoutRow(_ w: HKWorkout) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(w.workoutActivityType.name)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.35))
                    Text(w.startDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.55))
                }

                HStack(spacing: 0) {
                    let km = Self.distanceKm(w)
                    if km > 0 {
                        metric("거리", String(format: "%.2f", km), "km", Color(red: 0.35, green: 0.65, blue: 1.0))
                        Spacer()
                    }
                    metric("시간", "\(Int(w.duration / 60))", "분", .white)
                    if let cal = Self.calories(w) {
                        Spacer()
                        metric("칼로리", "\(Int(cal))", "", Color(red: 1.0, green: 0.65, blue: 0.2))
                    }
                    if let hr = Self.avgHR(w) {
                        Spacer()
                        metric("평균HR", "\(Int(hr))", "", Color(red: 1.0, green: 0.35, blue: 0.35))
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8)).foregroundStyle(Color(white: 0.55))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(color)
                if !unit.isEmpty { Text(unit).font(.system(size: 8)).foregroundStyle(Color(white: 0.5)) }
            }
        }
    }

    // MARK: - HKWorkout stat helpers

    static func distanceKm(_ w: HKWorkout) -> Double {
        if let m = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) {
            return m / 1000.0
        }
        if let m = w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter()) {
            return m / 1000.0
        }
        return 0
    }

    static func calories(_ w: HKWorkout) -> Double? {
        w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
    }

    static func avgHR(_ w: HKWorkout) -> Double? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        return w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: unit)
    }
}

// MARK: - Workout Detail with Route

struct WorkoutDetailView: View {
    let workout: HKWorkout

    @State private var locations: [CLLocation] = []
    @State private var distance: Double?
    @State private var pace: Double?

    var body: some View {
        WorkoutRouteView(
            locations: locations,
            workoutType: workout.workoutActivityType.name,
            date: workout.startDate,
            distance: distance,
            duration: workout.duration / 60.0,
            pace: pace
        )
        .onAppear { loadRoute() }
        #if os(iOS)
        .safeAreaInset(edge: .bottom) { flyoverBar }
        #endif
    }

    #if os(iOS)
    @ViewBuilder private var flyoverBar: some View {
        if locations.count >= 2 {
            NavigationLink {
                FlyoverReplayView(
                    locations: locations,
                    workoutType: workout.workoutActivityType.name,
                    date: workout.startDate
                )
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill").font(.system(size: 20))
                    Text("경로 플라이오버 영상").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "video.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal).padding(.bottom, 8)
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    private func loadRoute() {
        let meters = TrainingHistoryView.distanceKm(workout) * 1000.0
        if meters > 0 {
            distance = meters
            if workout.duration > 0 { pace = workout.duration / (meters / 1000.0) }
        }

        #if targetEnvironment(simulator)
        loadMockRoute()
        #else
        Task {
            let locs = (try? await HealthKitManager.shared.fetchWorkoutRoute(for: workout)) ?? []
            await MainActor.run { self.locations = locs }
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private func loadMockRoute() {
        // Mock: 한강 반포대교~동작대교 러닝 코스 (약 5km)
        let baseCoords: [(Double, Double)] = [
            (37.5080, 126.9950), (37.5082, 126.9970), (37.5085, 126.9995), (37.5083, 127.0020),
            (37.5080, 127.0045), (37.5078, 127.0070), (37.5075, 127.0095), (37.5073, 127.0120),
            (37.5070, 127.0145), (37.5068, 127.0170), (37.5072, 127.0175), (37.5075, 127.0150),
            (37.5078, 127.0125), (37.5080, 127.0100), (37.5082, 127.0075), (37.5084, 127.0050),
            (37.5083, 127.0025), (37.5081, 127.0000), (37.5080, 126.9975), (37.5079, 126.9950),
        ]
        var interpolated: [CLLocationCoordinate2D] = []
        for i in 0..<(baseCoords.count - 1) {
            let s = baseCoords[i], e = baseCoords[i + 1]
            for step in 0..<5 {
                let f = Double(step) / 5.0
                interpolated.append(.init(latitude: s.0 + (e.0 - s.0) * f, longitude: s.1 + (e.1 - s.1) * f))
            }
        }
        interpolated.append(.init(latitude: baseCoords.last!.0, longitude: baseCoords.last!.1))
        let now = Date()
        let count = interpolated.count
        locations = interpolated.enumerated().map { i, c in
            let p = Double(i) / Double(max(count - 1, 1))
            let altitude = 30.0 + 35.0 * sin(p * .pi) + 5.0 * sin(p * .pi * 6)
            return CLLocation(coordinate: c, altitude: altitude, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now)
        }
        if distance == nil { distance = 5000 }
        if pace == nil, workout.duration > 0 { pace = workout.duration / 5.0 }
    }
    #endif
}
