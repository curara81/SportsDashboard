import SwiftUI
import MapKit
import CoreLocation

struct WorkoutRouteView: View {
    let routeCoordinates: [CLLocationCoordinate2D]
    let workoutType: String
    let date: Date
    let distance: Double? // meters
    let duration: Double  // minutes
    let pace: Double?     // seconds per km

    @State private var mapPosition: MapCameraPosition = .automatic

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
