#if os(iOS)
import SwiftUI
import MapKit
import CoreLocation
import AVFoundation
import UIKit

// MARK: - Flyover Replay (animated route playback + video export)

/// Full-screen cinematic replay of a finished workout's GPS route.
/// - In-app: animated camera that follows the route as a colored polyline grows.
/// - Export: renders a shareable .mp4 (Apple 3D Flyover frames) on demand.
struct FlyoverReplayView: View {
    let workoutType: String
    let date: Date

    private let coords: [CLLocationCoordinate2D]
    private let cumDist: [Double]      // cumulative meters, same count as coords
    private let camDist: Double
    private let accent: Color
    private let accentUI: UIColor

    @State private var camera: MapCameraPosition = .automatic
    @State private var progress: Double = 0      // 0…1 along the route
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var speed: Double = 1          // 1× / 2× / 4×
    @State private var satellite = true
    @State private var shareItem: FlyoverShareItem?

    @StateObject private var exporter = FlyoverVideoExporter()

    private let baseDuration = 16.0   // seconds for a full 1× replay
    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    init(locations: [CLLocation], workoutType: String, date: Date) {
        self.workoutType = workoutType
        self.date = date
        let ds = FlyoverRoute.downsample(locations.map { $0.coordinate }, max: 1000)
        self.coords = ds
        self.cumDist = FlyoverRoute.cumulative(ds)
        self.camDist = FlyoverRoute.frameDistance(ds)
        let (c, u) = FlyoverRoute.colors(for: workoutType)
        self.accent = c
        self.accentUI = u
    }

    var body: some View {
        ZStack {
            if coords.count >= 2 {
                mapLayer
                overlay
            } else {
                emptyState
            }

            if exporter.isRendering {
                renderingOverlay
            }
        }
        .navigationTitle("경로 플라이오버")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { updateCamera() }
        .onReceive(timer) { _ in tick() }
        .onChange(of: progress) { _, _ in if isScrubbing { updateCamera() } }
        .onChange(of: exporter.outputURL) { _, url in
            if let url { shareItem = FlyoverShareItem(url: url) }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
    }

    // MARK: Map

    private var mapLayer: some View {
        Map(position: $camera) {
            // Faint full route (where you'll go) + bright covered progress.
            MapPolyline(coordinates: coords)
                .stroke(.white.opacity(0.28), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            MapPolyline(coordinates: shownCoords)
                .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

            Annotation("", coordinate: coords[0]) {
                Circle().fill(.green)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            Annotation("", coordinate: headCoord) {
                ZStack {
                    Circle().fill(.white).frame(width: 18, height: 18)
                    Circle().fill(accent).frame(width: 11, height: 11)
                }
                .shadow(radius: 3)
            }
        }
        .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
        .allowsHitTesting(!isPlaying)
        .ignoresSafeArea()
    }

    // MARK: Overlay UI

    private var overlay: some View {
        VStack {
            titleChip
            Spacer()
            controlPanel
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var titleChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.run")
            Text(workoutType).fontWeight(.semibold)
            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                .foregroundStyle(.secondary)
            Spacer()
            Button { satellite.toggle() } label: {
                Image(systemName: satellite ? "globe.americas.fill" : "map.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var controlPanel: some View {
        VStack(spacing: 10) {
            // Live stats
            HStack {
                stat(String(format: "%.2f", coveredMeters / 1000), "km 진행")
                Spacer()
                stat("\(Int(progress * 100))", "%")
                Spacer()
                stat(String(format: "%.2f", totalMeters / 1000), "km 전체")
            }

            // Scrubber
            Slider(value: $progress, in: 0...1) { editing in
                isScrubbing = editing
                if editing { isPlaying = false }
                if !editing { updateCamera() }
            }
            .tint(accent)

            // Transport
            HStack(spacing: 14) {
                Button { cycleSpeed() } label: {
                    Text("\(Int(speed))×")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Button { togglePlay() } label: {
                    Image(systemName: progress >= 1 ? "arrow.counterclockwise" : (isPlaying ? "pause.fill" : "play.fill"))
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 60, height: 60)
                        .background(accent, in: Circle())
                        .foregroundStyle(.white)
                }

                Button { startExport() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            Button { startExport() } label: {
                Label("영상으로 저장 (.mp4)", systemImage: "film")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var renderingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: exporter.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(accent)
                Text("영상 렌더링 중… \(Int(exporter.progress * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("3D 플라이오버 프레임 합성 중. 잠시만요.")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "map").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("GPS 경로 없음").font(.headline)
            Text("이 운동에는 저장된 경로 데이터가 없습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: Playback

    private func tick() {
        guard isPlaying, !isScrubbing, coords.count >= 2 else { return }
        let step = (1.0 / 30.0) * speed / baseDuration
        progress = min(1, progress + step)
        updateCamera()
        if progress >= 1 { isPlaying = false }
    }

    private func togglePlay() {
        if progress >= 1 { progress = 0 }
        isPlaying.toggle()
        if isPlaying { updateCamera() }
    }

    private func cycleSpeed() { speed = speed >= 4 ? 1 : speed * 2 }

    private func updateCamera() {
        guard coords.count >= 2 else { return }
        let (i, _) = idxFrac
        let look = min(i + max(1, coords.count / 40), coords.count - 1)
        let heading = FlyoverRoute.bearing(coords[i], coords[look])
        camera = .camera(MapCamera(centerCoordinate: headCoord, distance: camDist, heading: heading, pitch: 55))
    }

    private func startExport() {
        isPlaying = false
        Task {
            await exporter.render(coords: coords, camDist: camDist, satellite: satellite, accent: accentUI)
        }
    }

    // MARK: Derived geometry

    private var idxFrac: (Int, Double) {
        guard coords.count >= 2 else { return (0, 0) }
        let f = progress * Double(coords.count - 1)
        let i = min(Int(f), coords.count - 2)
        return (i, f - Double(i))
    }

    private var headCoord: CLLocationCoordinate2D {
        guard coords.count >= 2 else { return coords.first ?? CLLocationCoordinate2D() }
        let (i, t) = idxFrac
        return FlyoverRoute.interp(coords[i], coords[i + 1], t)
    }

    private var shownCoords: [CLLocationCoordinate2D] {
        guard coords.count >= 2 else { return coords }
        let (i, _) = idxFrac
        return Array(coords[0...i]) + [headCoord]
    }

    private var coveredMeters: Double {
        guard cumDist.count == coords.count, coords.count >= 2 else { return 0 }
        let (i, t) = idxFrac
        return cumDist[i] + (cumDist[i + 1] - cumDist[i]) * t
    }

    private var totalMeters: Double { cumDist.last ?? 0 }
}

// MARK: - Route geometry helpers

enum FlyoverRoute {
    static func downsample(_ c: [CLLocationCoordinate2D], max: Int) -> [CLLocationCoordinate2D] {
        guard c.count > max, max > 1 else { return c }
        let step = Double(c.count - 1) / Double(max - 1)
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(max)
        for i in 0..<max { out.append(c[Int((Double(i) * step).rounded())]) }
        return out
    }

    static func cumulative(_ c: [CLLocationCoordinate2D]) -> [Double] {
        guard c.count >= 1 else { return [] }
        var out = [0.0]
        out.reserveCapacity(c.count)
        for i in 1..<c.count {
            let a = CLLocation(latitude: c[i - 1].latitude, longitude: c[i - 1].longitude)
            let b = CLLocation(latitude: c[i].latitude, longitude: c[i].longitude)
            out.append(out[i - 1] + b.distance(from: a))
        }
        return out
    }

    static func frameDistance(_ c: [CLLocationCoordinate2D]) -> Double {
        guard c.count >= 2 else { return 800 }
        let lats = c.map { $0.latitude }, lons = c.map { $0.longitude }
        let a = CLLocation(latitude: lats.min()!, longitude: lons.min()!)
        let b = CLLocation(latitude: lats.max()!, longitude: lons.max()!)
        return min(Swift.max(b.distance(from: a) * 0.55, 500), 2500)
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func interp(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    static func colors(for type: String) -> (Color, UIColor) {
        let t = type.lowercased()
        if type.contains("러닝") || t.contains("run") {
            return (Color(red: 0.2, green: 0.85, blue: 0.45), UIColor(red: 0.2, green: 0.85, blue: 0.45, alpha: 1))
        } else if type.contains("사이클") || t.contains("cycl") {
            return (Color(red: 1, green: 0.6, blue: 0.15), UIColor(red: 1, green: 0.6, blue: 0.15, alpha: 1))
        } else if type.contains("걷") || t.contains("walk") {
            return (Color(red: 0.3, green: 0.6, blue: 1), UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1))
        }
        return (Color(red: 1, green: 0.55, blue: 0.2), UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1))
    }
}

// MARK: - Video exporter (MKMapSnapshotter frames → AVAssetWriter mp4)

@MainActor
final class FlyoverVideoExporter: ObservableObject {
    @Published var isRendering = false
    @Published var progress: Double = 0
    @Published var outputURL: URL?
    @Published var errorText: String?

    func render(coords: [CLLocationCoordinate2D], camDist: Double, satellite: Bool, accent: UIColor) async {
        guard coords.count >= 2 else { return }
        isRendering = true
        progress = 0
        outputURL = nil
        errorText = nil
        do {
            let url = try await Self.renderVideo(
                coords: coords, camDist: camDist, satellite: satellite, accent: accent
            ) { p in
                Task { @MainActor [weak self] in self?.progress = p }
            }
            outputURL = url
        } catch {
            errorText = error.localizedDescription
        }
        isRendering = false
    }

    nonisolated static func renderVideo(
        coords: [CLLocationCoordinate2D],
        camDist: Double,
        satellite: Bool,
        accent: UIColor,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let fps = 30
        let duration = 16.0
        let total = Int(duration * Double(fps))
        let size = CGSize(width: 720, height: 1280)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flyover-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        guard writer.canAdd(input) else {
            throw NSError(domain: "flyover", code: -1, userInfo: [NSLocalizedDescriptionKey: "비디오 입력 추가 실패"])
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "flyover", code: -1)
        }
        writer.startSession(atSourceTime: .zero)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        for f in 0..<total {
            let p = total > 1 ? Double(f) / Double(total - 1) : 0
            let image = try await frameImage(
                progress: p, coords: coords, camDist: camDist,
                satellite: satellite, accent: accent, size: size, renderer: renderer
            )
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 8_000_000)
            }
            guard let pb = pixelBuffer(from: image, size: size) else { continue }
            let time = CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps))
            if !adaptor.append(pb, withPresentationTime: time) {
                throw writer.error ?? NSError(domain: "flyover", code: -2, userInfo: [NSLocalizedDescriptionKey: "프레임 쓰기 실패"])
            }
            onProgress(Double(f + 1) / Double(total))
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw writer.error ?? NSError(domain: "flyover", code: -3)
        }
        return url
    }

    nonisolated static func frameImage(
        progress p: Double,
        coords: [CLLocationCoordinate2D],
        camDist: Double,
        satellite: Bool,
        accent: UIColor,
        size: CGSize,
        renderer: UIGraphicsImageRenderer
    ) async throws -> UIImage {
        let n = coords.count
        let f = p * Double(n - 1)
        let i = min(Int(f), n - 2)
        let t = f - Double(i)
        let head = FlyoverRoute.interp(coords[i], coords[i + 1], t)
        let look = min(i + max(1, n / 40), n - 1)
        let heading = FlyoverRoute.bearing(coords[i], coords[look])

        let opts = MKMapSnapshotter.Options()
        opts.size = size
        opts.scale = 1
        opts.mapType = satellite ? .hybridFlyover : .standard
        opts.pointOfInterestFilter = .excludingAll
        opts.camera = MKMapCamera(lookingAtCenter: head, fromDistance: camDist, pitch: 55, heading: heading)

        let snapshot = try await MKMapSnapshotter(options: opts).start()

        return renderer.image { _ in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            var started = false
            for k in 0...i {
                let pt = snapshot.point(for: coords[k])
                if !started { path.move(to: pt); started = true }
                else { path.addLine(to: pt) }
            }
            path.addLine(to: snapshot.point(for: head))
            accent.setStroke()
            path.lineWidth = 7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

            let hp = snapshot.point(for: head)
            let dot = UIBezierPath(ovalIn: CGRect(x: hp.x - 9, y: hp.y - 9, width: 18, height: 18))
            UIColor.white.setFill(); dot.fill()
            accent.setStroke(); dot.lineWidth = 4; dot.stroke()

            let sp = snapshot.point(for: coords[0])
            let sdot = UIBezierPath(ovalIn: CGRect(x: sp.x - 7, y: sp.y - 7, width: 14, height: 14))
            UIColor.systemGreen.setFill(); sdot.fill()
            UIColor.white.setStroke(); sdot.lineWidth = 2; sdot.stroke()
        }
    }

    nonisolated static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB, attrs, &pb
        )
        guard status == kCVReturnSuccess, let buffer = pb, let cg = image.cgImage else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        ctx?.draw(cg, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

// MARK: - Share sheet + item

struct FlyoverShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
