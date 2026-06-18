import SwiftUI
import MapKit
import CoreLocation
import Charts

struct WorkoutRouteView: View {
    let locations: [CLLocation]
    let workoutType: String
    let date: Date
    let distance: Double? // meters
    let duration: Double  // minutes
    let pace: Double?     // seconds per km

    @State private var mapPosition: MapCameraPosition = .automatic

    private var routeCoordinates: [CLLocationCoordinate2D] {
        locations.map { $0.coordinate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("경로 지도")
                    .font(.system(size: 17, weight: .bold))

                if routeCoordinates.count >= 2 {
                    mapCard
                } else {
                    CardView {
                        HStack {
                            Image(systemName: "map.fill")
                                .foregroundStyle(Color(white: 0.4))
                            Text("GPS 경로 없음")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if hasElevationData {
                    elevationCard
                }

                summaryCard
            }
            .padding(.horizontal, 6)
        }
    }

    private var mapCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                Label("경로", systemImage: "map.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                Map(position: $mapPosition) {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(.green, lineWidth: 3)

                    if let first = routeCoordinates.first {
                        Annotation("출발", coordinate: first) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                        }
                    }

                    if let last = routeCoordinates.last {
                        Annotation("도착", coordinate: last) {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.35, blue: 0.35))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .mapStyle(.standard(elevation: .flat))
            }
        }
    }

    // MARK: - Elevation Profile

    private struct ElevationPoint: Identifiable {
        let id = UUID()
        let distanceKm: Double
        let altitude: Double
    }

    /// Cumulative distance (km) vs altitude (m) sampled along the route.
    private var elevationPoints: [ElevationPoint] {
        guard locations.count >= 2 else { return [] }
        var points: [ElevationPoint] = [ElevationPoint(distanceKm: 0, altitude: locations[0].altitude)]
        var cumDist = 0.0
        for i in 1..<locations.count {
            cumDist += locations[i].distance(from: locations[i - 1])
            points.append(ElevationPoint(distanceKm: cumDist / 1000, altitude: locations[i].altitude))
        }
        return points
    }

    /// Total ascent / descent (m) with a hysteresis filter to suppress GPS altitude jitter.
    private var ascentDescent: (ascent: Double, descent: Double) {
        guard locations.count >= 2 else { return (0, 0) }
        let threshold = 1.0 // meters — ignore changes smaller than this
        var ascent = 0.0
        var descent = 0.0
        var reference = locations[0].altitude
        for loc in locations.dropFirst() {
            let delta = loc.altitude - reference
            if delta > threshold {
                ascent += delta
                reference = loc.altitude
            } else if delta < -threshold {
                descent += -delta
                reference = loc.altitude
            }
        }
        return (ascent, descent)
    }

    /// Show the chart only when we have ≥2 points and a meaningful altitude spread.
    private var hasElevationData: Bool {
        let pts = elevationPoints
        guard pts.count >= 2 else { return false }
        let altitudes = pts.map { $0.altitude }
        guard let lo = altitudes.min(), let hi = altitudes.max() else { return false }
        return (hi - lo) > 1.0
    }

    private var elevationCard: some View {
        let pts = elevationPoints
        let summary = ascentDescent
        let altitudes = pts.map { $0.altitude }
        let minAlt = altitudes.min() ?? 0
        let maxAlt = altitudes.max() ?? 0

        return CardView {
            VStack(alignment: .leading, spacing: 6) {
                Label("고도 프로파일", systemImage: "mountain.2.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                Chart(pts) { point in
                    AreaMark(
                        x: .value("거리", point.distanceKm),
                        y: .value("고도", point.altitude)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color.orange.opacity(0.45), Color.orange.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("거리", point.distanceKm),
                        y: .value("고도", point.altitude)
                    )
                    .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: minAlt...max(maxAlt, minAlt + 1))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let km = value.as(Double.self) {
                                Text("\(String(format: "%.1f", km))km")
                                    .font(.system(size: 7))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let m = value.as(Double.self) {
                                Text("\(Int(m))")
                                    .font(.system(size: 7))
                            }
                        }
                    }
                }
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 0) {
                    elevationMetric(
                        icon: "arrow.up.right",
                        label: "상승",
                        value: "\(Int(summary.ascent))",
                        color: Color(red: 1.0, green: 0.45, blue: 0.35)
                    )
                    Spacer()
                    elevationMetric(
                        icon: "arrow.down.right",
                        label: "하강",
                        value: "\(Int(summary.descent))",
                        color: Color(red: 0.35, green: 0.65, blue: 1.0)
                    )
                    Spacer()
                    elevationMetric(
                        icon: "arrow.up.to.line",
                        label: "최고",
                        value: "\(Int(maxAlt))",
                        color: Color(white: 0.85)
                    )
                }
            }
        }
    }

    private func elevationMetric(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 7))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(Color(white: 0.55))
            }
            HStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text("m")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(white: 0.55))
            }
        }
    }

    private var summaryCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(workoutType)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.55))
                }

                HStack(spacing: 0) {
                    if let dist = distance {
                        routeMetric(
                            label: "거리",
                            value: String(format: "%.2f", dist / 1000),
                            unit: "km",
                            color: Color(red: 0.35, green: 0.65, blue: 1.0)
                        )
                    }
                    Spacer()
                    routeMetric(
                        label: "시간",
                        value: formatDuration(duration * 60),
                        unit: "",
                        color: .white
                    )
                    Spacer()
                    if let p = pace {
                        routeMetric(
                            label: "페이스",
                            value: formatPace(p),
                            unit: "/km",
                            color: Color(red: 0.3, green: 0.85, blue: 0.45)
                        )
                    }
                }

                if routeCoordinates.count >= 2 {
                    HStack {
                        Image(systemName: "location.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(white: 0.4))
                        Text("\(routeCoordinates.count) GPS 포인트")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
            }
        }
    }

    private func routeMetric(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(Color(white: 0.55))
            HStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatPace(_ secondsPerKm: Double) -> String {
        let m = Int(secondsPerKm) / 60
        let s = Int(secondsPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }
}
