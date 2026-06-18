# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Live GPS map page during a watch workout (real-time route, follow camera,
  distance/pace/time overlay).
- Post-workout route **flyover** replay on iPhone over a 3D satellite map
  (play/pause/scrub/speed), with `.mp4` export via `MKMapSnapshotter` +
  `AVAssetWriter` and a share sheet.
- Unit tests for `MetricsEngine` formulas (host-less macOS logic bundle).
- CI workflow: unit tests + watchOS/iOS compile on every push/PR.
- `README` (project overview, disclaimer/trademarks), `BUILDING.md`, `LICENSE`
  (PolyForm Noncommercial 1.0.0).

### Fixed
- Live map page trapped the swipe gesture, blocking navigation back to the
  metrics/controls pages; the active workout was lost when forced to exit.
  Map interaction disabled (camera auto-follows) and `WorkoutManager` ownership
  hoisted to `DashboardView` so the session survives navigation.

### Changed
- Removed the legacy duplicate `SportsDashboard/` sources (diverged copies of
  `HealthKitManager`/`MetricsEngine`); `project.yml` is now authoritative.
- Neutralized third-party brand names in source comments.
