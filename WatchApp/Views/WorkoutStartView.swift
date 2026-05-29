#if os(watchOS)
import SwiftUI

struct WorkoutStartView: View {
    @StateObject private var manager = WorkoutManager()

    var body: some View {
        Group {
            if manager.isActive {
                ActiveWorkoutView(manager: manager)
            } else {
                workoutSelector
            }
        }
    }

    // MARK: - Workout Selector

    private var workoutSelector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("운동 시작")
                    .font(.system(size: 17, weight: .bold))

                ForEach(WorkoutManager.SportType.allCases) { sport in
                    Button {
                        manager.startWorkout(type: sport)
                    } label: {
                        CardView {
                            HStack(spacing: 12) {
                                Image(systemName: sport.icon)
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(red: sport.color.r, green: sport.color.g, blue: sport.color.b))
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sport.rawValue)
                                        .font(.system(size: 15, weight: .bold))
                                    Text("자유 모드")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(white: 0.55))
                                }

                                Spacer()

                                Image(systemName: "play.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(red: sport.color.r, green: sport.color.g, blue: sport.color.b))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Pace-guided running shortcut
                NavigationLink {
                    RacePredictionView()
                } label: {
                    CardView {
                        HStack(spacing: 12) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(red: 0.7, green: 0.45, blue: 1.0))
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("페이스 러닝")
                                    .font(.system(size: 15, weight: .bold))
                                Text("목표 페이스 설정 후 시작")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(white: 0.55))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.35))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - Active Workout View

struct ActiveWorkoutView: View {
    @ObservedObject var manager: WorkoutManager

    private var sportColor: Color {
        Color(red: manager.workoutType.color.r,
              green: manager.workoutType.color.g,
              blue: manager.workoutType.color.b)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Status header
                statusHeader

                // Main metric
                mainMetricCard

                // Secondary metrics
                secondaryMetrics

                // HR card
                heartRateCard

                // Km split (pace sports only)
                if manager.workoutType.usePace && manager.currentKm > 0 {
                    kmSplitCard
                }

                // Controls
                controlButtons
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack {
            Image(systemName: manager.workoutType.icon)
                .font(.system(size: 12))
            Text(manager.workoutType.rawValue)
                .font(.system(size: 13, weight: .bold))
            Spacer()
            if !manager.isFreeMode {
                Text(manager.paceStatus.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(paceStatusColor)
            } else {
                Text("자유 모드")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
            }
        }
        .foregroundStyle(sportColor)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(sportColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Main Metric

    private var mainMetricCard: some View {
        CardView {
            VStack(spacing: 4) {
                if manager.workoutType.usePace {
                    // Pace display
                    Text("현재 페이스")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.55))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(manager.currentPace > 0 ? formatPace(manager.currentPace) : "--:--")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundStyle(manager.isFreeMode ? sportColor : paceStatusColor)
                        Text("/km")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.55))
                    }

                    if !manager.isFreeMode {
                        HStack(spacing: 12) {
                            miniMetric("목표", formatPace(manager.targetPacePerKm), Color(red: 0.35, green: 0.65, blue: 1.0))
                            miniMetric("평균", manager.averagePace > 0 ? formatPace(manager.averagePace) : "--:--", .white)
                        }
                    } else {
                        miniMetric("평균 페이스", manager.averagePace > 0 ? formatPace(manager.averagePace) + " /km" : "--:--", .white)
                    }
                } else {
                    // Speed display (cycling)
                    Text("현재 속도")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.55))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(manager.currentSpeed > 0 ? String(format: "%.1f", manager.currentSpeed * 3.6) : "--")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundStyle(sportColor)
                        Text("km/h")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    miniMetric("평균 속도", manager.averageSpeed > 0 ? String(format: "%.1f km/h", manager.averageSpeed * 3.6) : "--", .white)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Secondary Metrics

    private var secondaryMetrics: some View {
        CardView {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("거리")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(white: 0.55))
                    Text(String(format: "%.2f", manager.totalDistance / 1000))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    Text("km")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.55))
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("시간")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(white: 0.55))
                    Text(formatTime(manager.elapsedSeconds))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("칼로리")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(white: 0.55))
                    Text("\(Int(manager.activeCalories))")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.2))
                    Text("kcal")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
        }
    }

    // MARK: - Heart Rate

    private var heartRateCard: some View {
        CardView {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.35))
                    .font(.system(size: 14))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(manager.currentHeartRate > 0 ? "\(Int(manager.currentHeartRate))" : "--")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("bpm")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    if manager.averageHeartRate > 0 {
                        Text("평균 \(Int(manager.averageHeartRate))")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
            }
        }
    }

    // MARK: - Km Split

    private var kmSplitCard: some View {
        CardView {
            HStack {
                Text("\(manager.currentKm)km")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.55))
                Spacer()
                Text(formatPace(manager.lastKmPace))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(sportColor)
                Text("/km")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.55))
            }
        }
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 12) {
            Button {
                manager.togglePause()
            } label: {
                Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 44)
                    .background(Color(white: 0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                manager.endWorkout()
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("종료")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(red: 1.0, green: 0.35, blue: 0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var paceStatusColor: Color {
        switch manager.paceStatus {
        case .tooFast: return Color(red: 1.0, green: 0.65, blue: 0.2)
        case .onTarget: return Color(red: 0.3, green: 0.85, blue: 0.45)
        case .tooSlow: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .free: return sportColor
        }
    }

    private func miniMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(Color(white: 0.4))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatPace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite && secondsPerKm > 0 else { return "--:--" }
        let m = Int(secondsPerKm) / 60
        let s = Int(secondsPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }
}
#endif
