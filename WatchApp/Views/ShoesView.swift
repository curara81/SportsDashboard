import SwiftUI
import SwiftData
import HealthKit

/// Running-shoe mileage tracker. Each shoe's mileage = startKm + running distance
/// logged since it was added (summed from HealthKit). Flags shoes past retirementKm.
struct ShoesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Shoe.addedDate, order: .reverse) private var shoes: [Shoe]

    /// (date, km) for each running workout — summed per shoe by addedDate.
    @State private var runs: [(date: Date, km: Double)] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("신발")
                    .font(.system(size: 17, weight: .bold))

                Button {
                    ctx.insert(Shoe(name: "러닝화 \(shoes.count + 1)"))
                    try? ctx.save()
                } label: {
                    Label("신발 추가", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if shoes.isEmpty {
                    Text("신발을 추가하면 러닝 거리가 자동 누적됩니다")
                        .font(.system(size: 10)).foregroundStyle(Color(white: 0.5))
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(shoes) { shoe in
                        shoeCard(shoe)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .onAppear(perform: load)
    }

    private func mileageKm(_ shoe: Shoe) -> Double {
        shoe.startKm + runs.filter { $0.date >= shoe.addedDate }.reduce(0) { $0 + $1.km }
    }

    private func shoeCard(_ shoe: Shoe) -> some View {
        let km = mileageKm(shoe)
        let pct = min(km / max(shoe.retirementKm, 1), 1.0)
        let over = km >= shoe.retirementKm
        return CardView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(shoe.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(shoe.isRetired ? Color(white: 0.5) : .white)
                    Spacer()
                    if over && !shoe.isRetired {
                        Text("교체 권장")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.4))
                    } else if shoe.isRetired {
                        Text("은퇴")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", km))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(over ? Color(red: 1, green: 0.5, blue: 0.35) : Color(red: 0.35, green: 0.65, blue: 1.0))
                    Text("/ \(Int(shoe.retirementKm)) km")
                        .font(.system(size: 10)).foregroundStyle(Color(white: 0.55))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.2)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(over ? Color(red: 1, green: 0.5, blue: 0.35) : Color(red: 0.3, green: 0.85, blue: 0.45))
                            .frame(width: geo.size.width * pct, height: 6)
                    }
                }
                .frame(height: 6)

                Button {
                    shoe.isRetired.toggle()
                    try? ctx.save()
                } label: {
                    Text(shoe.isRetired ? "다시 사용" : "은퇴 처리")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        Task {
            let ws = (try? await HealthKitManager.shared.fetchWorkouts(daysBack: 365)) ?? []
            let runRows = ws
                .filter { $0.workoutActivityType == .running }
                .map { (date: $0.startDate, km: TrainingHistoryView.distanceKm($0)) }
                .filter { $0.km > 0 }
            await MainActor.run { self.runs = runRows }
        }
    }
}
