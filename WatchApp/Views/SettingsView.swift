import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile {
        profiles.first ?? UserProfile()
    }

    @State private var birthYear: Int = 1990
    @State private var isMale: Bool = true
    @State private var manualMaxHR: Double = 0
    @State private var restingHR: Double = 60
    @State private var targetSleep: Double = 8.0
    @State private var vt1Pct: Double = 0.75
    @State private var vt2Pct: Double = 0.88
    @State private var initialized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("설정")
                    .font(.system(size: 17, weight: .bold))

                basicInfoCard
                hrSettingsCard
                thresholdCard
                sleepCard
                infoCard
            }
            .padding(.horizontal, 6)
        }
        .onAppear {
            guard !initialized else { return }
            let p = profile
            birthYear = p.birthYear
            isMale = p.isMale
            manualMaxHR = p.manualMaxHR ?? 0
            restingHR = p.restingHR
            targetSleep = p.targetSleepHours
            vt1Pct = p.vt1Percentage
            vt2Pct = p.vt2Percentage
            initialized = true
        }
    }

    private var basicInfoCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("기본 정보", systemImage: "person.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                HStack {
                    Text("출생연도")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $birthYear) {
                        ForEach(1950...2010, id: \.self) { year in
                            Text("\(String(year))").tag(year)
                        }
                    }
                    .frame(width: 80, height: 36)
                    .onChange(of: birthYear) { save() }
                }

                HStack {
                    Text("성별")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $isMale) {
                        Text("남성").tag(true)
                        Text("여성").tag(false)
                    }
                    .frame(width: 100)
                    .onChange(of: isMale) { save() }
                }
            }
        }
    }

    private var hrSettingsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("심박수", systemImage: "heart.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("최대 심박수")
                            .font(.system(size: 12))
                        Spacer()
                        if manualMaxHR > 0 {
                            Text("\(Int(manualMaxHR)) bpm")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.35))
                        } else {
                            let est = 208 - 0.7 * Double(Calendar.current.component(.year, from: Date()) - birthYear)
                            Text("\(Int(est)) (추정)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                    }
                    Slider(value: $manualMaxHR, in: 0...220, step: 1)
                        .onChange(of: manualMaxHR) { save() }
                    Text("0 = Tanaka 공식 자동 추정")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.4))
                }

                HStack {
                    Text("안정시 심박수")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(Int(restingHR)) bpm")
                        .font(.system(size: 12, weight: .semibold))
                }
                Slider(value: $restingHR, in: 30...100, step: 1)
                    .onChange(of: restingHR) { save() }
            }
        }
    }

    private var thresholdCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("환기역치 (Lucia TRIMP)", systemImage: "lungs.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                HStack {
                    Text("VT1")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(Int(vt1Pct * 100))% HRmax")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                }
                Slider(value: $vt1Pct, in: 0.6...0.85, step: 0.01)
                    .onChange(of: vt1Pct) { save() }

                HStack {
                    Text("VT2")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(Int(vt2Pct * 100))% HRmax")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.2))
                }
                Slider(value: $vt2Pct, in: 0.8...0.95, step: 0.01)
                    .onChange(of: vt2Pct) { save() }
            }
        }
    }

    private var sleepCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Label("수면 목표", systemImage: "moon.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))

                HStack {
                    Text("목표 시간")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(targetSleep, specifier: "%.1f") 시간")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.45))
                }
                Slider(value: $targetSleep, in: 5...10, step: 0.5)
                    .onChange(of: targetSleep) { save() }
            }
        }
    }

    private var infoCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 4) {
                Label("SportsDashboard v1.0", systemImage: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                Text("Banister TRIMP · CTL/ATL/TSB · ACWR · Karvonen Zones · Riegel Race Prediction · Foster Monotony")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.4))
            }
        }
    }

    private func save() {
        let p: UserProfile
        if let existing = profiles.first {
            p = existing
        } else {
            p = UserProfile()
            modelContext.insert(p)
        }
        p.birthYear = birthYear
        p.isMale = isMale
        p.manualMaxHR = manualMaxHR > 0 ? manualMaxHR : nil
        p.restingHR = restingHR
        p.targetSleepHours = targetSleep
        p.vt1Percentage = vt1Pct
        p.vt2Percentage = vt2Pct
        try? modelContext.save()

        // Sync to iPhone
        SyncManager.shared.sendSettings(profile: p)
    }
}
