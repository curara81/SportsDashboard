import SwiftUI

/// "더보기" tab — menu of secondary screens (Garmin Connect's 자세히 equivalent).
struct iOSMoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("활동 목록", "list.bullet.clipboard", .blue) { TrainingHistoryView() }
                    row("레이스 예측", "flag.checkered", .green) { RacePredictionView() }
                }
                Section {
                    row("장비 (신발)", "shoe.2", .orange) { ShoesView() }
                }
                Section {
                    row("설정", "gearshape.fill", .gray) { iOSSettingsView() }
                }
            }
            .navigationTitle("더보기")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row<Destination: View>(_ title: String, _ icon: String, _ tint: Color,
                                        @ViewBuilder _ destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
        }
    }
}
