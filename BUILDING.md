# Building SportsDashboard

The Xcode project is **generated from `project.yml`** with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the single
source of truth. Do not hand-edit `SportsDashboard.xcodeproj`; it is regenerated.

## Requirements

- macOS with **Xcode 16** or newer
- **XcodeGen**: `brew install xcodegen`
- An Apple ID for code signing (a free Personal Team is enough to run on device)
- To run on hardware: an iPhone, and an Apple Watch paired to it

## Generate & open

```bash
xcodegen generate
open SportsDashboard.xcodeproj
```

Re-run `xcodegen generate` whenever you change `project.yml` or add/remove files.

- Files under `Shared/`, `WatchApp/`, and `iOSApp/` are picked up automatically
  (folder/group sources).
- The **iOS target** also compiles a few specific files from `WatchApp/Views`
  (they are shared UI). If you add a new `WatchApp` file that iOS must compile,
  list it under the `SportsDashboard` target `sources:` in `project.yml`.

## Code signing

Both apps use **Automatic** signing. The team is set in `project.yml`
(`DEVELOPMENT_TEAM`, 4 places: iOS + watch, Debug + Release).

- To use your own team: edit `DEVELOPMENT_TEAM` in `project.yml`, then
  `xcodegen generate`. (Setting it in Xcode's *Signing & Capabilities* works too,
  but is overwritten on the next regenerate — prefer `project.yml`.)
- **Free Personal Team:** provisioning profiles expire after **7 days**. If a
  build fails with a signing/profile error, just Run again from Xcode to refresh.

## Run on device

| Target | Scheme | Destination |
|--------|--------|-------------|
| Apple Watch | `SportsDashboard Watch App` | your Apple Watch |
| iPhone | `SportsDashboard` | your iPhone |

First watch install copies debug symbols and can take several minutes. If the
debugger reports `SIGKILL` on launch, it is the debugger attach — the app is
installed; just open it from the watch app list. Once installed, the watch app
runs standalone (the Mac↔watch debug link dropping does not stop it).

## Tests

MetricsEngine's formulas are covered by a **host-less macOS logic-test bundle**
(no simulator needed):

```bash
xcodebuild test \
  -project SportsDashboard.xcodeproj \
  -scheme Tests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## CI

`.github/workflows/ci.yml` runs on every push/PR: `xcodegen generate`, the unit
tests, and a compile of both the watchOS and iOS apps.
