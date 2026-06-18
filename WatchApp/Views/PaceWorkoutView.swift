#if os(watchOS)
import SwiftUI
import SwiftData

struct PaceWorkoutView: View {
    @StateObject private var manager = WorkoutManager()
    @Query private var profiles: [UserProfile]

    let targetDistance: String     // "5K", "10K", etc.
    let targetDistanceKm: Double
    let targetTimeSeconds: Double

    private var targetPacePerKm: Double {
        targetTimeSeconds / targetDistanceKm
    }

    private var zoneLowerBounds: [Double] {
        (profiles.first ?? UserProfile()).zones.map(\.lower)
    }

    var body: some View {
        Group {
            if manager.isCountingDown {
                CountdownView(
                    value: manager.countdownValue,
                    color: Color(red: 0.3, green: 0.85, blue: 0.45),
                    onCancel: { manager.cancelCountdown() }
                )
            } else if manager.isShowingSummary {
                WorkoutSummaryView(manager: manager)
            } else if manager.isActive {
                activeWorkoutView
            } else {
                preWorkoutView
            }
        }
    }

    // MARK: - Pre-Workout (Ready to Start)

    private var preWorkoutView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("페이스 러닝")
                    .font(.system(size: 17, weight: .bold))

                CardView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("목표", systemImage: "target")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(white: 0.55))

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(targetDistance)
                                    .font(.system(size: 20, weight: .bold))
                                Text("\(targetDistanceKm, specifier: "%.1f") km")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(white: 0.55))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatTime(targetTimeSeconds))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.45))
                                Text("목표 시간")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(white: 0.55))
                            }
                        }
                    }
                }

                CardView {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("목표 페이스", systemImage: "speedometer")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(white: 0.55))

                        HStack {
                            Text(formatPace(targetPacePerKm))
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                            Text("/km")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(white: 0.55))
                        }

                        Text("±15초 벗어나면 햅틱 알림")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.4))
                    }
                }

                Button {
                    manager.startWorkout(type: .running, targetPace: targetPacePerKm, zoneLowerBounds: zoneLowerBounds)
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("러닝 시작")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.3, green: 0.85, blue: 0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Active Workout

    private var activeWorkoutView: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Pace status indicator
                paceStatusBanner

                // Current pace (big)
                currentPaceCard

                // Distance + Time
                distanceTimeCard

                // Heart Rate
                heartRateCard

                // Km split
                kmSplitCard

                // Controls
                controlButtons
            }
            .padding(.horizontal, 6)
        }
    }

    private var paceStatusBanner: some View {
        HStack {
            Image(systemName: paceStatusIcon)
                .font(.system(size: 12))
            Text(manager.paceStatus.rawValue)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(paceStatusColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(paceStatusColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var currentPaceCard: some View {
        CardView {
            VStack(spacing: 4) {
                Text("현재 페이스")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.55))

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(manager.currentPace > 0 ? formatPace(manager.currentPace) : "--:--")
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .foregroundStyle(paceStatusColor)
                    Text("/km")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.55))
                }

                HStack(spacing: 12) {
                    VStack(spacing: 1) {
                        Text("목표")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(white: 0.4))
                        Text(formatPace(targetPacePerKm))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                    }
                    VStack(spacing: 1) {
                        Text("평균")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(white: 0.4))
                        Text(manager.averagePace > 0 ? formatPace(manager.averagePace) : "--:--")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var distanceTimeCard: some View {
        CardView {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("거리")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(white: 0.55))
                    Text(String(format: "%.2f", manager.totalDistance / 1000))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
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
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("남은 거리")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(white: 0.55))
                    let remaining = max(0, targetDistanceKm - manager.totalDistance / 1000)
                    Text(String(format: "%.2f", remaining))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.2))
                    Text("km")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
        }
    }

    private var heartRateCard: some View {
        CardView {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.35))
                    .font(.system(size: 14))
                Spacer()
                Text(manager.currentHeartRate > 0 ? "\(Int(manager.currentHeartRate))" : "--")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("bpm")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
            }
        }
    }

    private var kmSplitCard: some View {
        Group {
            if manager.currentKm > 0 {
                CardView {
                    HStack {
                        Text("최근 1km")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.55))
                        Spacer()
                        Text(formatPace(manager.lastKmPace))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(kmPaceColor(manager.lastKmPace))
                        Text("/km")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 12) {
            // Pause/Resume
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

            // End
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

    private var paceStatusIcon: String {
        switch manager.paceStatus {
        case .tooFast: return "hare.fill"
        case .onTarget: return "checkmark.circle.fill"
        case .tooSlow: return "tortoise.fill"
        case .free: return "figure.run"
        }
    }

    private var paceStatusColor: Color {
        switch manager.paceStatus {
        case .tooFast: return Color(red: 1.0, green: 0.65, blue: 0.2)
        case .onTarget: return Color(red: 0.3, green: 0.85, blue: 0.45)
        case .tooSlow: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .free: return Color(red: 0.3, green: 0.85, blue: 0.45)
        }
    }

    private func kmPaceColor(_ pace: Double) -> Color {
        let diff = pace - targetPacePerKm
        if abs(diff) <= paceToleranceSeconds { return Color(red: 0.3, green: 0.85, blue: 0.45) }
        if diff < 0 { return Color(red: 1.0, green: 0.65, blue: 0.2) }
        return Color(red: 1.0, green: 0.35, blue: 0.35)
    }

    private var paceToleranceSeconds: Double { 15 }

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
