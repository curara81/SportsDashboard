import SwiftUI
import SwiftData

struct iOSSettingsView: View {
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
        Form {
            Section("기본 정보") {
                Picker("출생연도", selection: $birthYear) {
                    ForEach(1950...2010, id: \.self) { year in
                        Text("\(String(year))").tag(year)
                    }
                }
                .onChange(of: birthYear) { save() }

                Picker("성별", selection: $isMale) {
                    Text("남성").tag(true)
                    Text("여성").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: isMale) { save() }
            }

            Section("심박수") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("최대 심박수")
                        Spacer()
                        if manualMaxHR > 0 {
                            Text("\(Int(manualMaxHR)) bpm").foregroundStyle(.red)
                        } else {
                            let est = 208 - 0.7 * Double(Calendar.current.component(.year, from: Date()) - birthYear)
                            Text("\(Int(est)) (추정)").foregroundStyle(.secondary)
                        }
                    }
                    Slider(value: $manualMaxHR, in: 0...220, step: 1)
                        .onChange(of: manualMaxHR) { save() }
                    Text("0 = Tanaka 공식 자동 추정")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("안정시 심박수")
                        Spacer()
                        Text("\(Int(restingHR)) bpm").bold()
                    }
                    Slider(value: $restingHR, in: 30...100, step: 1)
                        .onChange(of: restingHR) { save() }
                }
            }

            Section("환기역치 (Lucia TRIMP)") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("VT1")
                        Spacer()
                        Text("\(Int(vt1Pct * 100))% HRmax").foregroundStyle(.blue)
                    }
                    Slider(value: $vt1Pct, in: 0.6...0.85, step: 0.01)
                        .onChange(of: vt1Pct) { save() }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("VT2")
                        Spacer()
                        Text("\(Int(vt2Pct * 100))% HRmax").foregroundStyle(.orange)
                    }
                    Slider(value: $vt2Pct, in: 0.8...0.95, step: 0.01)
                        .onChange(of: vt2Pct) { save() }
                }
            }

            Section("수면 목표") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("목표 시간")
                        Spacer()
                        Text("\(targetSleep, specifier: "%.1f") 시간").foregroundStyle(.green)
                    }
                    Slider(value: $targetSleep, in: 5...10, step: 0.5)
                        .onChange(of: targetSleep) { save() }
                }
            }

            Section("정보") {
                LabeledContent("버전", value: "1.0")
                Text("Banister TRIMP · CTL/ATL/TSB · ACWR · Karvonen Zones · Riegel Race Prediction · Foster Monotony")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("설정")
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

        // Sync to Apple Watch
        SyncManager.shared.sendSettings(profile: p)
    }
}
