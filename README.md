# SportsDashboard

A standalone **Apple Watch + iPhone** training dashboard built on Apple HealthKit —
live workout tracking, a real-time GPS map on the watch, advanced training-load
analytics, and post-workout route **flyover** replays (with shareable video) on the phone.

> **Personal / educational open-source project.** Not affiliated with any fitness brand.
> See [Disclaimer & Trademarks](#disclaimer--trademarks).

## What is this?

SportsDashboard turns an Apple Watch and iPhone into a serious training-analytics tool.
It records outdoor workouts (run / walk / cycle) through HealthKit, shows rich live
metrics and a moving GPS map while you train, saves the workout (with its GPS route)
back to Apple Health, and on the phone it renders a cinematic **route flyover** of any
recorded run that can be exported as an `.mp4` to share.

All training-load and readiness analytics are computed from **openly published
sports-science formulas** — not from any vendor's proprietary algorithm.

## Why I built it

I wanted the kind of advanced training insight that dedicated fitness watches (such as
Garmin) offer — training load, readiness, recovery, route maps, route replays — but
running **natively on Apple Watch + HealthKit**, computed from **public, peer-reviewed
formulas** instead of closed proprietary models.

It started as a personal learning project: how far can you get toward "premium fitness
watch" analytics using only Apple's frameworks and open sports-science research? It is
released publicly so others can learn from it, build on it, or adapt it for their own use.

## Features

**Apple Watch (watchOS 10+)**
- Live workout: heart rate, pace, distance, speed, cadence, calories
- Live HR zones (Karvonen) with time-in-zone, auto-pause, manual + auto laps
- **Live GPS map page** — route polyline drawn in real time, follow camera, current position
- Elevation / ascent / descent; pace guidance with haptics
- Saves a full `HKWorkout` with attached GPS route

**iPhone (iOS 17+)**
- Morning readiness report (sleep + HRV + RHR)
- Training balance (CTL / ATL / TSB), ACWR, training status, recovery time
- VO₂max estimate, fitness age, race prediction, weekly trends, workout history
- **Route flyover replay** over a 3D satellite map (play / pause / scrub / speed)
- **Video export** (`.mp4`) of the flyover via `MKMapSnapshotter` + `AVAssetWriter`

**Analytics (all from public literature)**
- TRIMP (Banister / Edwards / Lúcia), CTL/ATL/TSB fitness–fatigue model
- ACWR (acute:chronic workload ratio), Riegel race-time prediction
- Karvonen HR zones, heart-rate recovery, cardiac drift, monotony / strain

## Tech stack

SwiftUI · HealthKit · CoreLocation · MapKit · Swift Charts · AVFoundation ·
WatchConnectivity · SwiftData. Targets watchOS 10 / iOS 17.

## Disclaimer & Trademarks

- **Not affiliated with, endorsed by, or connected to** Garmin, Firstbeat, Apple,
  Strava, Nike, or any other company. All product names and trademarks are the property
  of their respective owners and are used here only **nominatively**, for description and
  comparison.
- Metrics are **approximations derived from public sports-science research**, not the
  proprietary algorithms of any vendor. No Firstbeat-branded metric (e.g. Body Battery)
  or proprietary algorithm is used or reproduced.
- **Not a medical device.** Provided for informational and educational purposes only;
  it is not intended to diagnose, treat, or prevent any condition.
- Maps and flyover videos use **Apple Maps**; map data © Apple and its data providers.
  Apple Maps attribution must be preserved where map content is displayed or shared.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) — free to use, modify, and share for
**noncommercial** (personal, educational, research) purposes. Commercial use requires a
separate license from the author.

Required Notice: Copyright © 2026 curara81
