# App Rename: PillDaddy → Routine Dose Planner

**Date:** 2026-06-21
**Status:** Approved, executing directly (greenfield rename, no migration)

## Motivation

The name "PillDaddy" collides with an existing App Store product at pilldaddy.com.
The app is renamed to **Routine Dose Planner**, which is available in the App Store
and fits the app's verb-oriented domain ("plan doses," "follow your routine").

## Locked decisions

| Aspect | Value |
|---|---|
| Display name (`CFBundleDisplayName`) | **Routine Dose Planner** |
| Conversational short name | **Routine** |
| Xcode target / Swift module / directory | **RoutineDosePlanner** |
| App bundle id | `rodeo.fm.routine` |
| Widget bundle id | `rodeo.fm.routine.widgets` |
| CloudKit container | `iCloud.rodeo.fm.routine` |
| URL scheme | `routine` |
| Migration | **None** — pre-release; single tester reinstalls |

### Naming-collision note

`Routine` is already a first-class SwiftData `@Model` in the app
(`Models/Routine.swift`). The code-level module/target is therefore named
`RoutineDosePlanner`, **not** bare `Routine`, to avoid `Routine` (module) vs
`Routine` (type) ambiguity. The user-facing name and bundle id are unaffected.

## Scope of change

### A. Xcode project & targets (`project.yml`)
- `name: PillDaddy` → `RoutineDosePlanner`
- Targets `PillDaddy` / `PillDaddyTests` / `PillDaddyWidgets`
  → `RoutineDosePlanner` / `RoutineDosePlannerTests` / `RoutineDosePlannerWidgets`
- App target: explicit `PRODUCT_BUNDLE_IDENTIFIER: rodeo.fm.routine`
  (keeps the long target name out of the bundle id)
- Widget target: `PRODUCT_BUNDLE_IDENTIFIER: rodeo.fm.routine.widgets`
- App `CFBundleDisplayName: Routine Dose Planner`
- Widget `CFBundleDisplayName: PillDaddy Reminders` → `Routine Reminders`
- Scheme renamed; `.xcodeproj` regenerated → `RoutineDosePlanner.xcodeproj`

### B. Directories & files
- `PillDaddy/` → `RoutineDosePlanner/`
- `PillDaddyTests/` → `RoutineDosePlannerTests/`
- `PillDaddyWidgets/` → `RoutineDosePlannerWidgets/`
- `PillDaddy.entitlements` → `RoutineDosePlanner.entitlements`
- `PillDaddyApp.swift` → `RoutineDosePlannerApp.swift`
- `Models/PillDaddySchema.swift` → `Models/RoutineSchema.swift`
- `PillDaddyWidgetsBundle.swift` → `RoutineDosePlannerWidgetsBundle.swift`

### C. Swift symbols
- `PillDaddyApp` → `RoutineDosePlannerApp`
- `PillDaddySchema` → `RoutineSchema`
- `PillDaddyWidgetsBundle` → `RoutineDosePlannerWidgetsBundle`
- Bare `PillDaddy` tokens in comments/strings updated

### D. Entitlements / CloudKit
- `com.apple.developer.icloud-container-identifiers`:
  `iCloud.rodeo.fm.PillDaddy` → `iCloud.rodeo.fm.routine`
- No Swift change — `ModelConfiguration` uses `cloudKitDatabase: .automatic`

### E. URL scheme
- `pilldaddy` → `routine` in `Info.plist`, `RoutineDosePlannerApp.swift`
  (host check), and `PillReminderLiveActivity.swift` (`widgetURL`)
- Deep links become `routine://routine/<routineID>`

### F. Usage strings
- `NSHealthUpdateUsageDescription`: "PillDaddy saves the patient's health
  readings…" → "Routine Dose Planner saves the patient's health readings…"

### G. Docs
- `README.md`, `AGENTS.md` (CLAUDE.md symlink), `EXPORT.md` updated
- Historical `docs/superpowers/specs|plans/*` left as-is (dated record)

### H. Web marketing site (`web/`)
- `index.html`, `privacy.html`, `support.html`: name swap **and** copy
  modernization ("regimes" → "routines", per the prior domain rename)

## Out of scope — manual external steps (cannot be automated here)

1. **Apple Developer portal**: register App IDs `rodeo.fm.routine` and
   `rodeo.fm.routine.widgets`, enable HealthKit + CloudKit, create CloudKit
   container `iCloud.rodeo.fm.routine`, regenerate provisioning profiles.
2. **Vercel**: rename the project / update the custom domain.
3. **App Store Connect / TestFlight**: new app record under the new bundle id.

## Verification (per CLAUDE.md core rules)

1. `xcodegen generate`
2. `xcodebuild build` — must compile and link cleanly
3. `xcodebuild test` on **iPhone 17** simulator — suite green
4. `grep -ri pilldaddy` over code/config returns nothing outside `docs/`
5. Commit locally

## Execution approach

Single mechanical pass (no behavior change; existing test suite is the
regression guard):

1. Edit `project.yml`
2. `git mv` directories and files
3. Find-replace symbols, strings, scheme, container id
4. Update entitlements / Info.plist / usage strings
5. Update README / AGENTS.md / EXPORT.md and `web/`
6. `xcodegen generate` → build → test on iPhone 17
7. Commit
