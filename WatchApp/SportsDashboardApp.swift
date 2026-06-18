import SwiftUI
import SwiftData

@main
struct SportsDashboardApp: App {

    init() {
        SyncManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.light)
                .onAppear { setupSyncReceiver() }
        }
        .modelContainer(for: [
            DailyTrainingLoad.self,
            DailyReadiness.self,
            BodyCompositionRecord.self,
            UserProfile.self,
            Shoe.self
        ])
    }

    private func setupSyncReceiver() {
        SyncManager.shared.onSettingsReceived = { data in
            // Apply received settings from iPhone
            let container = try? ModelContainer(for: UserProfile.self)
            guard let context = container?.mainContext else { return }
            let descriptor = FetchDescriptor<UserProfile>()
            let profile = (try? context.fetch(descriptor).first) ?? UserProfile()
            if (try? context.fetch(descriptor))?.isEmpty ?? true {
                context.insert(profile)
            }
            SyncManager.shared.applySettings(data, to: profile)
            try? context.save()
        }
    }
}
