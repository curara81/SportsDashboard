import SwiftUI

struct HRZonesView: View {
    let profile: UserProfile

    private var zones: [(name: String, range: String, low: Double, high: Double, color: Color)] {
        let maxHR = profile.effectiveMaxHR
        let rhr = profile.restingHR
        let hrr = maxHR - rhr

        return [
            ("Z5 최대", "\(Int(rhr + hrr * 0.9))–\(Int(maxHR))", 0.9, 1.0, Color(red: 1.0, green: 0.2, blue: 0.2)),
            ("Z4 무산소", "\(Int(rhr + hrr * 0.8))–\(Int(rhr + hrr * 0.9))", 0.8, 0.9, Color(red: 1.0, green: 0.5, blue: 0.2)),
            ("Z3 유산소", "\(Int(rhr + hrr * 0.7))–\(Int(rhr + hrr * 0.8))", 0.7, 0.8, Color(red: 0.3, green: 0.85, blue: 0.45)),
            ("Z2 지방연소", "\(Int(rhr + hrr * 0.6))–\(Int(rhr + hrr * 0.7))", 0.6, 0.7, Color(red: 0.35, green: 0.65, blue: 1.0)),
            ("Z1 워밍업", "\(Int(rhr + hrr * 0.5))–\(Int(rhr + hrr * 0.6))", 0.5, 0.6, Color(white: 0.5)),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("심박수 존")
                    .font(.system(size: 17, weight: .bold))

                profileInfo
                zonesList
            }
            .padding(.horizontal, 6)
        }
    }

    private var profileInfo: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                Label("프로필", systemImage: "person.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                HStack(spacing: 0) {
                    infoItem(label: "나이", value: "\(profile.age)세")
                    Spacer()
                    infoItem(label: "최대HR", value: "\(Int(profile.effectiveMaxHR))")
                    Spacer()
                    infoItem(label: "안정HR", value: "\(Int(profile.restingHR))")
                    Spacer()
                    infoItem(label: "HRR", value: "\(Int(profile.heartRateReserve))")
                }
            }
        }
    }

    private var zonesList: some View {
        VStack(spacing: 6) {
            ForEach(zones, id: \.name) { zone in
                CardView {
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(zone.color)
                            .frame(width: 4, height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(zone.name)
                                .font(.system(size: 12, weight: .semibold))
                            Text(zone.range + " bpm")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.55))
                        }

                        Spacer()

                        Text("\(Int(zone.low * 100))–\(Int(zone.high * 100))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(zone.color)
                    }
                }
            }
        }
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(Color(white: 0.55))
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded))
        }
    }
}
