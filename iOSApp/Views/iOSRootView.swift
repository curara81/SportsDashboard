import SwiftUI

/// Tab-bar root for the iPhone app (Garmin-Connect-style): 홈 · 캘린더 · 더보기.
struct iOSRootView: View {
    var body: some View {
        TabView {
            iOSDashboardView()
                .tabItem { Label("홈", systemImage: "house.fill") }

            iOSCalendarView()
                .tabItem { Label("캘린더", systemImage: "calendar") }

            iOSMoreView()
                .tabItem { Label("더보기", systemImage: "ellipsis.circle") }
        }
    }
}
