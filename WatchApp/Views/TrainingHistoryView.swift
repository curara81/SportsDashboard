import SwiftUI
import CoreLocation

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
                        NavigationLink {
                            WorkoutDetailView(load: load)
                        } label: {
                            workoutRow(load)
                        }
                        .buttonStyle(.plain)
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.35))
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

// MARK: - Workout Detail with Route

struct WorkoutDetailView: View {
    let load: DailyTrainingLoad

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var isLoadingRoute = false
    @State private var distance: Double?
    @State private var pace: Double?

    var body: some View {
        WorkoutRouteView(
            routeCoordinates: routeCoordinates,
            workoutType: load.workoutType ?? "운동",
            date: load.date,
            distance: distance,
            duration: load.durationMinutes,
            pace: pace
        )
        .onAppear { loadRoute() }
    }

    private func loadRoute() {
        isLoadingRoute = true

        #if targetEnvironment(simulator)
        loadMockRoute()
        #else
        Task {
            await fetchRealRoute()
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private func loadMockRoute() {
        // Mock: 한강 반포대교~동작대교 러닝 코스 (약 5km)
        let baseCoords: [(Double, Double)] = [
            (37.5080, 126.9950),  // 반포한강공원
            (37.5082, 126.9970),
            (37.5085, 126.9995),
            (37.5083, 127.0020),
            (37.5080, 127.0045),
            (37.5078, 127.0070),
            (37.5075, 127.0095),
            (37.5073, 127.0120),
            (37.5070, 127.0145),  // 동작대교 방향
            (37.5068, 127.0170),
            (37.5072, 127.0175),  // 턴어라운드
            (37.5075, 127.0150),
            (37.5078, 127.0125),
            (37.5080, 127.0100),
            (37.5082, 127.0075),
            (37.5084, 127.0050),
            (37.5083, 127.0025),
            (37.5081, 127.0000),
            (37.5080, 126.9975),
            (37.5079, 126.9950),  // 복귀
        ]

        // Add slight jitter for realism
        var coords: [CLLocationCoordinate2D] = []
        for (lat, lon) in baseCoords {
            let jitterLat = Double.random(in: -0.0002...0.0002)
            let jitterLon = Double.random(in: -0.0002...0.0002)
            coords.append(CLLocationCoordinate2D(latitude: lat + jitterLat, longitude: lon + jitterLon))
        }

        // Interpolate between points for smoother line
        var interpolated: [CLLocationCoordinate2D] = []
        for i in 0..<(coords.count - 1) {
            let start = coords[i]
            let end = coords[i + 1]
            let steps = 5
            for s in 0..<steps {
                let fraction = Double(s) / Double(steps)
                let lat = start.latitude + (end.latitude - start.latitude) * fraction
                let lon = start.longitude + (end.longitude - start.longitude) * fraction
                interpolated.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        interpolated.append(coords.last!)

        self.routeCoordinates = interpolated
        self.distance = 5000 // 5km
        self.pace = (load.durationMinutes * 60) / 5.0 // seconds per km
        isLoadingRoute = false
    }
    #endif

    private func fetchRealRoute() async {
        do {
            let workouts = try await HealthKitManager.shared.fetchWorkouts(daysBack: 90)
            // Find workout matching this load's date
            let cal = Calendar.current
            guard let workout = workouts.first(where: {
                cal.isDate($0.startDate, inSameDayAs: load.date)
            }) else {
                isLoadingRoute = false
                return
            }

            let locations = try await HealthKitManager.shared.fetchWorkoutRoute(for: workout)
            let coords = locations.map { $0.coordinate }

            // Calculate total distance
            var totalDist = 0.0
            for i in 1..<locations.count {
                totalDist += locations[i].distance(from: locations[i - 1])
            }

            await MainActor.run {
                self.routeCoordinates = coords
                self.distance = totalDist
                if totalDist > 0 {
                    self.pace = (load.durationMinutes * 60) / (totalDist / 1000)
                }
                self.isLoadingRoute = false
            }
        } catch {
            await MainActor.run {
                isLoadingRoute = false
            }
        }
    }
}
