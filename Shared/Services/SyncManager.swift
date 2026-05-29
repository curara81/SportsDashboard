import Foundation
import WatchConnectivity
import Combine

/// Bidirectional settings sync between iPhone and Apple Watch via WCSession.
final class SyncManager: NSObject, ObservableObject {

    static let shared = SyncManager()

    @Published var isReachable = false

    /// Callback when settings arrive from the other device
    var onSettingsReceived: (([String: Any]) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Activate

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Send Settings

    func sendSettings(profile: UserProfile) {
        guard WCSession.default.activationState == .activated else { return }

        let data: [String: Any] = [
            "birthYear": profile.birthYear,
            "isMale": profile.isMale,
            "maxHR": profile.maxHR,
            "restingHR": profile.restingHR,
            "targetSleepHours": profile.targetSleepHours,
            "vt1Percentage": profile.vt1Percentage,
            "vt2Percentage": profile.vt2Percentage,
            "syncTimestamp": Date().timeIntervalSince1970
        ]

        // transferUserInfo queues and guarantees delivery (even if watch is not reachable now)
        WCSession.default.transferUserInfo(data)
    }

    // MARK: - Apply Received Settings

    func applySettings(_ data: [String: Any], to profile: UserProfile) {
        if let v = data["birthYear"] as? Int { profile.birthYear = v }
        if let v = data["isMale"] as? Bool { profile.isMale = v }
        if let v = data["maxHR"] as? Double { profile.maxHR = v }
        if let v = data["restingHR"] as? Double { profile.restingHR = v }
        if let v = data["targetSleepHours"] as? Double { profile.targetSleepHours = v }
        if let v = data["vt1Percentage"] as? Double { profile.vt1Percentage = v }
        if let v = data["vt2Percentage"] as? Double { profile.vt2Percentage = v }
    }
}

// MARK: - WCSessionDelegate

extension SyncManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    // Received queued user info (guaranteed delivery)
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async {
            self.onSettingsReceived?(userInfo)
        }
    }

    // Received immediate message (if both apps are active)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.onSettingsReceived?(message)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    // iOS-only required delegate methods
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate after switching Apple Watch
        WCSession.default.activate()
    }
    #endif
}
