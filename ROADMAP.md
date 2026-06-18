# Runner+ Roadmap — fitness-watch running parity

Status: ✅ done · 🔨 in progress · ⬜ planned · 🔒 premium/needs accessory · ❌ not possible

Build/install: see [BUILDING.md](BUILDING.md). All work is committed per-feature; the
watch app installs from Xcode (scheme **SportsDashboard Watch App** → your Apple Watch).

## Run-feedback fixes (from real runs)
- ✅ #3 Workout history now lists real HKWorkouts (saved runs always appear)
- ✅ #2 Real auto-pause (freezes timer on stop, auto-resumes on movement)
- ✅ #6 Bigger live-map stats (distance/time/pace/avg in a 2×2 panel)
- ✅ #1 Current + average pace shown together (primary + map)
- ✅ #7 Korean voice km-split announcements (current split + average)
- ✅ GAP (grade-adjusted pace) — verifies/augments GPS pace with slope correction
- ⚠️ #4 Return to app after Siri/music takeover — NOT possible via public watchOS API
  (no programmatic foreground; governed by watchOS auto-return setting). Deferred.
- ⚠️ #5 Wrist-raise → show pace 5s → revert — watchOS controls wake; reliable/clean
  implementation not available, conflicts with manual paging. Deferred.

## ✅ Done (this work)
- GPS workout-route save/load authorization fix (HKSeriesType.workoutRoute)
- Garmin-style Digital-Crown vertical data screens, big text (`.verticalPage`)
- Live running dynamics: running power, stride length, vertical oscillation, ground contact
- Live GPS map page (swipe-safe) + post-run flyover replay + mp4 export (iPhone)
- App renamed to **Runner+** (display name)
- Virtual Partner / Ghost Runner (gap vs target-pace runner + haptic)
- Grade-Adjusted Pace (GAP, Minetti) + live grade %
- Live finish-time projection (5K/10K/half/full)
- Cadence coach (target-relative color)

## 🔨 Phase 2 — pacing & guidance (nearly done)
- ✅ Virtual Partner · ✅ GAP · ✅ finish projection · ✅ cadence coach (visual)
- ✅ Structured / interval workouts (presets + auto-advancing steps + step banner)
- ⬜ **Dual-target cues (pace + HR range, directional haptics, priority rule)** ← RESUME HERE
- ⬜ Cadence-coach haptic nudge (visual color already done)
- ⬜ Per-step pace/HR targets for interval steps (IntervalStep.targetPace exists; wire alerts)
- ⬜ On-watch interval builder UI (presets exist; add custom builder)

## 🔨 Phase 3 — navigation
- ✅ Back-to-Start / TracBack (compass arrow + straight-line distance, no course needed)
- ⬜ **GPX course infra** (needs iPhone import + WatchConnectivity sync + course store) ← big
- ⬜ Course turn-by-turn + off-route haptic alert (cross-track distance vs polyline)
- ⬜ ClimbPro (pre-segment loaded route elevation into climbs; live remaining grade/ascent)
- ⬜ Route Roulette (generate a target-distance loop from current location, MapKit)

## 🔨 Phase 4 — intelligence
- ✅ Burner: live fat/carb substrate split from intensity (data screen)
- ✅ Cardio Fitness level (VO2max → age/sex tier, on dashboard) + tests
- ⬜ Target Load (daily how-much-to-train band) + deterministic Daily Run recommendation
- ⬜ VDOT-based race prediction (blend VO2max + load) — upgrade Riegel
- ⬜ Cardiac decoupling live (extend existing cardiac-drift) = aerobic durability
- ⬜ Form Drift Detector (fatigue from running-dynamics decay + cue)

## ⬜ Phase 5 — safety & extras
- Safety Beacon: Action Button + 86 dB siren + Find My live share + dead-man timer
- Adaptive fueling/hydration coach (sweat-rate learning)
- Heat/altitude auto-derating of pace targets
- Shoe mileage tracking + retirement reminder
- Auto-highlights reel on the flyover (fastest km, PR, HR peak)

## 🔒 Premium / needs accessory
- ZoneSense (DDFA real-time metabolic zones) — needs BLE chest strap (Polar H10) via CoreBluetooth
- Audio Ghost (AirPods spatial-audio pacer)
- Adaptive training plan (Coach) — iPhone/backend; route any LLM via **Vertex AI** (per CLAUDE.md cost rule), not AI Studio Gemini
- Treadmill auto-calibration (per-pace stride model)

## ❌ Not possible on Apple Watch
- Running Economy, Step Speed Loss (Garmin HRM-600 chest-strap only)
- Exact Firstbeat numbers (VO2max/Body Battery/Training Effect identical values) — approximations only
- Developer multiband-GNSS control, Garmin onboard topo routing engine

---

## RESUME HERE → Structured / interval workouts

Goal: define a run as ordered steps (warmup → repeat[work + recovery]×N → cooldown),
each step with a target (pace range / HR zone / distance / time), and have the watch
auto-advance with haptic + screen cues at each transition.

Recommended approach (from research):
- **WorkoutKit** `CustomWorkout` / `IntervalBlock` / `IntervalStep` (.work/.recovery)
  with `PaceRangeAlert` / `HeartRateRangeAlert` and distance/time goals — auto-advance
  + alerts are built in. Author on iPhone, sync to watch. OR a simpler in-house step
  state machine driven by the existing HKWorkoutSession loop + WKInterfaceDevice haptics
  (reuses our lap/auto-pause/pace-haptic infra) if WorkoutKit integration is heavy.
- Start with a small preset library (e.g. 5×400m, 4×1km, pyramid) selectable on-watch,
  before a full builder UI.
- Files to touch: new `WatchApp/Models/IntervalWorkout.swift` (step model),
  `WatchApp/Services/WorkoutManager.swift` (step state + transitions),
  `WatchApp/Views/WorkoutStartView.swift` (step prompt UI + a workout picker).

Everything else: pick the next ⬜ item by phase order.
