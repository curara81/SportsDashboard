#if os(watchOS)
import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct WorkoutStartView: View {
    @StateObject private var manager = WorkoutManager()
    @Query private var profiles: [UserProfile]

    /// If set, immediately starts this sport (skips the selector grid).
    var autoStart: WorkoutManager.SportType? = nil
    @State private var didAutoStart = false

    private var zoneLowerBounds: [Double] {
        (profiles.first ?? UserProfile()).zones.map(\.lower)
    }

    var body: some View {
        Group {
            if manager.isCountingDown {
                CountdownView(
                    value: manager.countdownValue,
                    color: Color(red: manager.workoutType.color.r,
                                 green: manager.workoutType.color.g,
                                 blue: manager.workoutType.color.b),
                    onCancel: { manager.cancelCountdown() }
                )
            } else if manager.isShowingSummary {
                WorkoutSummaryView(manager: manager)
            } else if manager.isActive {
                ActiveWorkoutView(manager: manager)
            } else {
                workoutSelector
            }
        }
        .onAppear {
            // Quick-start chip → begin chosen sport immediately, once.
            if let sport = autoStart, !didAutoStart {
                didAutoStart = true
                manager.startWorkout(type: sport, zoneLowerBounds: zoneLowerBounds)
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
                        manager.startWorkout(type: sport, zoneLowerBounds: zoneLowerBounds)
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

// MARK: - Countdown View (shared, 3-2-1 before start)

struct CountdownView: View {
    let value: Int
    let color: Color
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            color.opacity(0.12).ignoresSafeArea()

            VStack(spacing: 4) {
                Text("\(max(value, 1))")
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText(countsDown: true))
                    .id(value)
                Text("준비")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.6))
            }

            VStack {
                Spacer()
                Button(action: onCancel) {
                    Text("취소")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.7))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 16)
                        .background(Color(white: 0.2))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 2)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
    }
}

// MARK: - Active Workout View (Apple-style paged: Controls | Metrics)

struct ActiveWorkoutView: View {
    @ObservedObject var manager: WorkoutManager
    @State private var page = 1   // start on Metrics; swipe left for Controls
    @State private var mapCamera: MapCameraPosition = .userLocation(fallback: .automatic)

    private var sportColor: Color {
        Color(red: manager.workoutType.color.r,
              green: manager.workoutType.color.g,
              blue: manager.workoutType.color.b)
    }

    var body: some View {
        // Apple Workout layout: [Controls] | [Metrics] | [Map] | [Now Playing]
        // Start on Metrics (center). Swipe right→Controls, left→Map→Music.
        TabView(selection: $page) {
            controlsPage.tag(0)
            metricsPage.tag(1)
            mapPage.tag(2)
            nowPlayingPage.tag(3)
        }
        .tabViewStyle(.page)
    }

    // MARK: - Active Status Bar (운동 중 + 큰 타이머, always shown so user KNOWS it started)

    private var activeStatusBar: some View {
        let paused = manager.isPaused || manager.isAutoPaused
        let statusColor = paused ? Color(red: 1.0, green: 0.7, blue: 0.0) : sportColor
        let label = manager.isAutoPaused ? "자동 일시정지" : (manager.isPaused ? "일시정지됨" : "운동 중")
        return VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: !paused)
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
                Spacer()
                Image(systemName: manager.workoutType.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.6))
            }
            Text(formatTime(manager.elapsedSeconds))
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(statusColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Controls Page (left swipe target — big Apple-style buttons)

    private var controlsPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("제어")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)

                // End (big red)
                Button {
                    manager.endWorkout()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20))
                        Text("종료")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color(red: 1.0, green: 0.3, blue: 0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                // Pause / Resume (big yellow/green)
                Button {
                    manager.togglePause()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 20))
                        Text(manager.isPaused ? "재개" : "일시정지")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(manager.isPaused
                                ? Color(red: 0.3, green: 0.85, blue: 0.45)
                                : Color(red: 1.0, green: 0.8, blue: 0.0))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                // Lap button (pace sports)
                if manager.workoutType.usePace {
                    Button {
                        manager.recordLap(isManual: true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 16))
                            Text("랩")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(white: 0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }

                // Auto-pause toggle
                Button {
                    manager.autoPauseEnabled.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: manager.autoPauseEnabled ? "pause.circle.fill" : "pause.circle")
                            .font(.system(size: 14))
                        Text("자동 일시정지")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(manager.autoPauseEnabled ? "켜짐" : "꺼짐")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(manager.autoPauseEnabled ? sportColor : Color(white: 0.5))
                    }
                    .foregroundStyle(Color(white: 0.7))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color(white: 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Text("측정값 →")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.4))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Metrics Page (center — default)

    private var metricsPage: some View {
        ScrollView {
            VStack(spacing: 8) {
                // BIG active indicator + timer (so user knows workout started)
                activeStatusBar

                // Main metric
                mainMetricCard

                // Secondary metrics
                secondaryMetrics

                // GPS / elevation / cadence
                gpsCard

                // HR card
                heartRateCard

                // HR zone live gauge
                if manager.zoneSeconds.reduce(0, +) > 0 {
                    hrZoneGauge
                }

                // Km split (pace sports only)
                if manager.workoutType.usePace && manager.currentKm > 0 {
                    kmSplitCard
                }

                // Laps so far
                if !manager.laps.isEmpty {
                    lapsCard
                }

                // Inline controls — ALWAYS visible so user can pause/stop
                // without needing to find the swipe page.
                HStack(spacing: 10) {
                    Button {
                        manager.togglePause()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 16))
                            Text(manager.isPaused ? "재개" : "일시정지")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(manager.isPaused
                                    ? Color(red: 0.3, green: 0.85, blue: 0.45)
                                    : Color(red: 1.0, green: 0.8, blue: 0.0))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button {
                        manager.endWorkout()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 50)
                            .background(Color(red: 1.0, green: 0.3, blue: 0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)

                Text("← 제어 · 지도 →")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Live Map Page (Garmin-style real-time route + position)

    private var mapPage: some View {
        ZStack(alignment: .bottom) {
            if manager.routeCoordinates.isEmpty {
                // No GPS fix yet — searching placeholder instead of a blank gray map.
                VStack(spacing: 6) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(sportColor)
                        .symbolEffect(.pulse, options: .repeating)
                    Text(manager.gpsAccuracy < 0 ? "GPS 검색 중…" : "위치 대기 중")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("← 측정값")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.4))
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Map(position: $mapCamera) {
                    UserAnnotation()   // current position (system blue dot)

                    if manager.routeCoordinates.count >= 2 {
                        MapPolyline(coordinates: manager.routeCoordinates)
                            .stroke(sportColor,
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }

                    if let start = manager.routeCoordinates.first {
                        Annotation("", coordinate: start) {
                            Circle()
                                .fill(.white)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(sportColor, lineWidth: 2))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .ignoresSafeArea(edges: .bottom)

                // Recenter — re-engage follow after a manual pan (top trailing).
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation { mapCamera = .userLocation(fallback: .automatic) }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(8)

                // Live stat strip — distance · pace/speed · time.
                HStack(spacing: 0) {
                    mapStatPill(String(format: "%.2f", manager.totalDistance / 1000), "km")
                    Spacer()
                    if manager.workoutType.usePace {
                        mapStatPill(manager.currentPace > 0 ? formatPace(manager.currentPace) : "--:--", "/km")
                    } else {
                        mapStatPill(manager.currentSpeed > 0 ? String(format: "%.1f", manager.currentSpeed * 3.6) : "--", "km/h")
                    }
                    Spacer()
                    mapStatPill(formatTime(manager.elapsedSeconds), "")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
        }
    }

    private func mapStatPill(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 8))
                    .foregroundStyle(Color(white: 0.7))
            }
        }
    }

    // MARK: - Now Playing Page (right swipe target)

    private var nowPlayingPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("음악")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)

                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.45))
                    .padding(.top, 8)

                Text("재생 중인 음악 제어")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text("워치 측면 버튼을 누르거나\n제어 센터에서 음악을\n제어할 수 있습니다")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.55))
                    .multilineTextAlignment(.center)

                Text("← 지도")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
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
                            miniMetric("속도", manager.currentSpeed > 0 ? String(format: "%.1f", manager.currentSpeed * 3.6) : "--", sportColor)
                        }
                    } else {
                        HStack(spacing: 12) {
                            miniMetric("평균", manager.averagePace > 0 ? formatPace(manager.averagePace) + "/km" : "--:--", .white)
                            miniMetric("속도", manager.currentSpeed > 0 ? String(format: "%.1f km/h", manager.currentSpeed * 3.6) : "--", sportColor)
                        }
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

    // MARK: - GPS / Elevation / Cadence

    private var gpsCard: some View {
        CardView {
            VStack(spacing: 6) {
                // GPS status row
                HStack(spacing: 4) {
                    Image(systemName: manager.hasGPSFix ? "location.fill" : "location.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(manager.hasGPSFix
                                         ? Color(red: 0.3, green: 0.85, blue: 0.45)
                                         : Color(red: 1.0, green: 0.65, blue: 0.2))
                    Text(manager.hasGPSFix ? "GPS 연결됨" : (manager.gpsAccuracy < 0 ? "GPS 검색 중…" : "GPS 약함"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.6))
                    Spacer()
                    if manager.routePointCount > 0 {
                        Text("\(manager.routePointCount)pt")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
                Divider()
                // Elevation + cadence row
                HStack(spacing: 0) {
                    VStack(spacing: 1) {
                        Text("오르막")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(white: 0.55))
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.3))
                            Text("\(Int(manager.totalAscent))")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }
                        Text("m").font(.system(size: 8)).foregroundStyle(Color(white: 0.5))
                    }
                    Spacer()
                    VStack(spacing: 1) {
                        Text("내리막")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(white: 0.55))
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.down.right")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                            Text("\(Int(manager.totalDescent))")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }
                        Text("m").font(.system(size: 8)).foregroundStyle(Color(white: 0.5))
                    }
                    Spacer()
                    VStack(spacing: 1) {
                        Text("케이던스")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(white: 0.55))
                        Text(manager.currentCadence > 0 ? "\(Int(manager.currentCadence))" : "--")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(sportColor)
                        Text("spm").font(.system(size: 8)).foregroundStyle(Color(white: 0.5))
                    }
                }
            }
        }
    }

    // MARK: - HR Zone Gauge (live time-in-zone)

    private var zoneColors: [Color] {
        [Color(red: 0.4, green: 0.7, blue: 1.0),   // Z1 blue
         Color(red: 0.3, green: 0.85, blue: 0.45), // Z2 green
         Color(red: 1.0, green: 0.8, blue: 0.2),   // Z3 yellow
         Color(red: 1.0, green: 0.55, blue: 0.2),  // Z4 orange
         Color(red: 1.0, green: 0.35, blue: 0.35)] // Z5 red
    }

    private var hrZoneGauge: some View {
        let total = max(manager.zoneSeconds.reduce(0, +), 1)
        return CardView {
            VStack(alignment: .leading, spacing: 5) {
                Text("심박 존")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                // Stacked bar
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { i in
                            zoneColors[i]
                                .frame(width: max(geo.size.width * manager.zoneSeconds[i] / total, manager.zoneSeconds[i] > 0 ? 2 : 0))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 12)
                // Per-zone time (only zones with time)
                ForEach(0..<5, id: \.self) { i in
                    if manager.zoneSeconds[i] > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(zoneColors[i]).frame(width: 6, height: 6)
                            Text("Z\(i+1)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(zoneColors[i])
                            Spacer()
                            Text(formatTime(manager.zoneSeconds[i]))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color(white: 0.7))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Laps card

    private var lapsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 4) {
                Text("랩")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                ForEach(manager.laps.suffix(5).reversed()) { lap in
                    HStack {
                        Text("\(lap.index)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(sportColor)
                            .frame(width: 16, alignment: .leading)
                        Text(String(format: "%.2fkm", lap.distance / 1000))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(white: 0.7))
                        Spacer()
                        Text(formatPace(lap.avgPace))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        if lap.avgHR > 0 {
                            Text("\(Int(lap.avgHR))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
                                .frame(width: 26, alignment: .trailing)
                        }
                    }
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

// MARK: - Workout Summary (저장 / 삭제 prompt — Garmin-style)

struct WorkoutSummaryView: View {
    @ObservedObject var manager: WorkoutManager

    private var sportColor: Color {
        Color(red: manager.workoutType.color.r,
              green: manager.workoutType.color.g,
              blue: manager.workoutType.color.b)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Header
                VStack(spacing: 2) {
                    Image(systemName: manager.workoutType.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(sportColor)
                    Text("운동 요약")
                        .font(.system(size: 15, weight: .bold))
                    Text(manager.workoutType.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.55))
                }
                .padding(.top, 4)

                // Summary metrics grid
                CardView {
                    VStack(spacing: 8) {
                        summaryRow("시간", formatTime(manager.summaryDuration), .white)
                        Divider()
                        summaryRow("거리", String(format: "%.2f km", manager.summaryDistance / 1000), sportColor)
                        Divider()
                        if manager.workoutType.usePace {
                            summaryRow("평균 페이스", manager.summaryAvgPace > 0 ? formatPace(manager.summaryAvgPace) + " /km" : "--", .white)
                            Divider()
                        }
                        summaryRow("평균 심박", manager.summaryAvgHR > 0 ? "\(Int(manager.summaryAvgHR)) bpm" : "--", Color(red: 1.0, green: 0.35, blue: 0.35))
                        Divider()
                        summaryRow("칼로리", "\(Int(manager.summaryCalories)) kcal", Color(red: 1.0, green: 0.65, blue: 0.2))
                        if manager.summaryAscent > 0 {
                            Divider()
                            summaryRow("오르막", "\(Int(manager.summaryAscent)) m", Color(red: 1.0, green: 0.5, blue: 0.3))
                        }
                    }
                }

                // Training Effect
                trainingEffectCard

                // HR zone distribution
                if manager.zoneSeconds.reduce(0, +) > 0 {
                    summaryZoneCard
                }

                // Lap splits
                if !manager.laps.isEmpty {
                    summaryLapsCard
                }

                // Save button (big green)
                Button {
                    manager.saveWorkout()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                        Text("저장")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(red: 0.3, green: 0.85, blue: 0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Text("건강 앱에 저장됩니다")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.45))

                // Discard button (red, less prominent)
                Button {
                    manager.discardWorkout()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                        Text("삭제")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(white: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
        }
    }

    private func summaryRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.6))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    // Training Effect card
    private var trainingEffectCard: some View {
        let te = MetricsEngine.trainingEffect(zoneSeconds: manager.zoneSeconds)
        return CardView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("트레이닝 효과", systemImage: "bolt.heart")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(white: 0.55))
                    Spacer()
                    Text(te.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(sportColor)
                }
                teBar("유산소", te.aerobic, Color(red: 0.3, green: 0.85, blue: 0.45))
                teBar("무산소", te.anaerobic, Color(red: 1.0, green: 0.45, blue: 0.35))
            }
        }
    }

    private func teBar(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.55))
                .frame(width: 30, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.18))
                    Capsule().fill(color).frame(width: geo.size.width * min(value / 5.0, 1.0))
                }
            }
            .frame(height: 8)
            Text(String(format: "%.1f", value))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 26, alignment: .trailing)
        }
    }

    // HR zone distribution card
    private var summaryZoneCard: some View {
        let zc: [Color] = [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.3, green: 0.85, blue: 0.45),
                           Color(red: 1.0, green: 0.8, blue: 0.2), Color(red: 1.0, green: 0.55, blue: 0.2),
                           Color(red: 1.0, green: 0.35, blue: 0.35)]
        let total = max(manager.zoneSeconds.reduce(0, +), 1)
        return CardView {
            VStack(alignment: .leading, spacing: 5) {
                Text("심박 존 분포")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { i in
                            zc[i].frame(width: max(geo.size.width * manager.zoneSeconds[i] / total, manager.zoneSeconds[i] > 0 ? 2 : 0))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 14)
                ForEach(0..<5, id: \.self) { i in
                    if manager.zoneSeconds[i] > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(zc[i]).frame(width: 6, height: 6)
                            Text("Z\(i+1)").font(.system(size: 9, weight: .semibold)).foregroundStyle(zc[i])
                            Spacer()
                            Text(formatTime(manager.zoneSeconds[i])).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color(white: 0.7))
                        }
                    }
                }
            }
        }
    }

    // Lap splits card
    private var summaryLapsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 4) {
                Text("랩 (\(manager.laps.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                ForEach(manager.laps) { lap in
                    HStack {
                        Text("\(lap.index)").font(.system(size: 10, weight: .bold)).foregroundStyle(sportColor).frame(width: 16, alignment: .leading)
                        Text(String(format: "%.2fkm", lap.distance / 1000)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(white: 0.7))
                        Spacer()
                        Text(formatPace(lap.avgPace)).font(.system(size: 10, weight: .semibold, design: .monospaced))
                        if lap.avgHR > 0 {
                            Text("\(Int(lap.avgHR))").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4)).frame(width: 26, alignment: .trailing)
                        }
                    }
                }
            }
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
