import SwiftUI

struct RunningDynamicsView: View {
    let power: Double?
    let cadence: Double?
    let gct: Double?
    let verticalOsc: Double?
    let strideLength: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("러닝 다이내믹스")
                    .font(.system(size: 17, weight: .bold))

                if let p = power {
                    dynamicCard(
                        icon: "bolt.fill",
                        title: "러닝 파워",
                        value: "\(Int(p))",
                        unit: "W",
                        color: Color(red: 1.0, green: 0.65, blue: 0.2),
                        rating: nil,
                        detail: "추진력 + 중력 저항 총합"
                    )
                }

                if let c = cadence {
                    let rating = MetricsEngine.RunningDynamicsEval.rateCadence(c)
                    dynamicCard(
                        icon: "metronome.fill",
                        title: "케이던스",
                        value: "\(Int(c))",
                        unit: "spm",
                        color: Color(red: 0.35, green: 0.65, blue: 1.0),
                        rating: rating,
                        detail: "분당 보폭 수 (180+ 이상적)"
                    )
                }

                if let g = gct {
                    let rating = MetricsEngine.RunningDynamicsEval.rateGCT(g)
                    dynamicCard(
                        icon: "shoe.fill",
                        title: "지면 접촉 시간",
                        value: "\(Int(g))",
                        unit: "ms",
                        color: Color(red: 0.3, green: 0.85, blue: 0.45),
                        rating: rating,
                        detail: "짧을수록 효율적 (< 240ms 양호)"
                    )
                }

                if let v = verticalOsc {
                    let rating = MetricsEngine.RunningDynamicsEval.rateVO(v)
                    dynamicCard(
                        icon: "arrow.up.arrow.down",
                        title: "수직 진동",
                        value: String(format: "%.1f", v),
                        unit: "cm",
                        color: Color(red: 0.7, green: 0.45, blue: 1.0),
                        rating: rating,
                        detail: "작을수록 에너지 낭비 줄임"
                    )
                }

                if let s = strideLength {
                    let rating = MetricsEngine.RunningDynamicsEval.rateStride(s)
                    dynamicCard(
                        icon: "figure.run",
                        title: "보폭",
                        value: String(format: "%.2f", s),
                        unit: "m",
                        color: Color(red: 0.3, green: 0.8, blue: 0.85),
                        rating: rating,
                        detail: "과도한 오버스트라이드 주의"
                    )
                }

                if power == nil && cadence == nil && gct == nil {
                    CardView {
                        VStack(spacing: 6) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 24))
                                .foregroundStyle(Color(white: 0.3))
                            Text("러닝 데이터 없음")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                            Text("Apple Workout으로 러닝 기록 시 자동 수집")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(white: 0.4))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func dynamicCard(
        icon: String, title: String, value: String, unit: String,
        color: Color, rating: String?, detail: String
    ) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(white: 0.55))
                    Spacer()
                    if let r = rating {
                        StatusBadge(label: r)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.55))
                }

                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.4))
            }
        }
    }
}
