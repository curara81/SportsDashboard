import SwiftUI
import SwiftData

@main
struct SportsDashboardApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [
            DailyTrainingLoad.self,
            DailyReadiness.self,
            BodyCompositionRecord.self,
            UserProfile.self
        ])
    }
}
