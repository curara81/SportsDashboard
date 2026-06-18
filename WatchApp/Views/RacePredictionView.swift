import SwiftUI

struct RacePredictionView: View {
    @State private var recentDistance: Double = 5.0
    @State private var recentMinutes: Int = 25
    @State private var recentSeconds: Int = 0
    @State private var autoFilled = false
    @State private var didLoad = false
    @State private var vdot: Double = 0

    private let distances: [(name: String, km: Double)] = [
        ("5K", 5.0), ("10K", 10.0), ("하프", 21.0975), ("풀", 42.195)
    ]

    private var baseTime: TimeInterval {
        Double(recentMinutes * 60 + recentSeconds)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("레이스 예측")
                    .font(.system(size: 17, weight: .bold))

                if autoFilled {
                    Text("최근 베스트 기록 자동 적용됨")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.45))
                }

                inputCard
                resultCards
                vdotCard
                paceCard
            }
            .padding(.horizontal, 6)
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            if let vo2 = try? await HealthKitManager.shared.fetchVO2max(), let last = vo2.last?.value {
                vdot = last
            }
            if let best = try? await HealthKitManager.shared.fetchBestRecentRun() {
                // Snap distance to the nearest standard bucket for the picker.
                let snapped = distances.min(by: { abs($0.km - best.distanceKm) < abs($1.km - best.distanceKm) })?.km ?? 5.0
                // Scale the time to the snapped distance via Riegel so the picker stays consistent.
                let scaledTime = MetricsEngine.predictRaceTime(knownDistance: best.distanceKm, knownTime: best.time, targetDistance: snapped)
                recentDistance = snapped
                recentMinutes = Int(scaledTime) / 60
                recentSeconds = Int(scaledTime) % 60
                autoFilled = true
            }
        }
    }

    @ViewBuilder private var vdotCard: some View {
        if vdot > 0 {
            CardView {
                VStack(alignment: .leading, spacing: 6) {
                    Label("VO2max 기반 예측 (VDOT \(Int(vdot)))", systemImage: "lungs.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(white: 0.55))
                    ForEach(distances, id: \.km) { d in
                        HStack {
                            Text(d.name)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 44, alignment: .leading)
                            Spacer()
                            Text(formatRaceTime(MetricsEngine.vdotRaceTime(vdot: vdot, distanceMeters: d.km * 1000)))
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.3, green: 0.8, blue: 0.85))
                        }
                    }
                }
            }
        }
    }

    private func formatRaceTime(_ s: TimeInterval) -> String {
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60, sec = Int(s) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private var inputCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("기준 기록", systemImage: "figure.run")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                HStack {
                    Text("거리")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.55))
                    Spacer()
                    Picker("", selection: $recentDistance) {
                        ForEach(distances, id: \.km) { d in
                            Text(d.name).tag(d.km)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 40)
                }

                HStack {
                    Text("기록")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.55))
                    Spacer()
                    HStack(spacing: 2) {
                        Picker("", selection: $recentMinutes) {
                            ForEach(10..<300) { m in
                                Text("\(m)").tag(m)
                            }
                        }
                        .frame(width: 45, height: 40)
                        Text(":")
                            .font(.system(size: 14, weight: .bold))
                        Picker("", selection: $recentSeconds) {
                            ForEach(0..<60) { s in
                                Text(String(format: "%02d", s)).tag(s)
                            }
                        }
                        .frame(width: 45, height: 40)
                    }
                }
            }
        }
    }

    private var resultCards: some View {
        ForEach(distances, id: \.km) { target in
            let predicted = MetricsEngine.predictRaceTime(
                knownDistance: recentDistance * 1000,
                knownTime: baseTime,
                targetDistance: target.km * 1000
            )
            let isSame = abs(target.km - recentDistance) < 0.01

            CardView {
                VStack(spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isSame ? Color(white: 0.55) : .white)
                            Text("\(target.km, specifier: "%.1f") km")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        if isSame {
                            Text(formatTime(baseTime))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(white: 0.55))
                            Text("기준")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(white: 0.4))
                        } else {
                            Text(formatTime(predicted))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.45))
                        }
                    }
                    #if os(watchOS)
                    if !isSame {
                        NavigationLink {
                            PaceWorkoutView(
                                targetDistance: target.name,
                                targetDistanceKm: target.km,
                                targetTimeSeconds: predicted
                            )
                        } label: {
                            HStack {
                                Image(systemName: "figure.run")
                                    .font(.system(size: 9))
                                Text("이 페이스로 달리기")
                                    .font(.system(size: 10, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8))
                            }
                            .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                        }
                        .buttonStyle(.plain)
                    }
                    #endif
                }
            }
        }
    }

    private var paceCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                Label("예측 페이스", systemImage: "speedometer")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                ForEach(distances, id: \.km) { target in
                    let predicted = MetricsEngine.predictRaceTime(
                        knownDistance: recentDistance * 1000,
                        knownTime: baseTime,
                        targetDistance: target.km * 1000
                    )
                    let pacePerKm = predicted / target.km

                    HStack {
                        Text(target.name)
                            .font(.system(size: 11))
                            .frame(width: 30, alignment: .leading)
                        Spacer()
                        Text(formatPace(pacePerKm) + " /km")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                    }
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatPace(_ secondsPerKm: Double) -> String {
        let m = Int(secondsPerKm) / 60
        let s = Int(secondsPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }
}
