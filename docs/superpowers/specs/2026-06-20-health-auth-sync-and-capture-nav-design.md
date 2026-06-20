# Health: Authorization Visibility, Retroactive Sync & Capture-Screen Navigation — Design

**Date:** 2026-06-20
**Status:** Approved (pending spec review)

This spec covers two independent improvements to the Health tab introduced in Session 6:

- **Feature A — Capture-screen navigation push.** Fix the jarring double-modal transition when adding a reading.
- **Feature B — HealthKit authorization visibility & retroactive sync.** Make partial-permission state visible and recoverable, and sync previously-captured rows once permission is granted.

They share no code and can be implemented in either order, but are specced and planned together because both touch the Health surfaces.

---

## Background

Session 6 added a Health tab with a generic `HealthMetric` SwiftData model, a `MetricRegistry`, a pure `HealthSampleMapper`, a `HealthKitWriting` protocol (live writer + test fake), and a `HealthMetricService` that does **persist-then-best-effort-write**: a reading is always saved locally, and the write to Apple Health is attempted but allowed to fail, leaving `healthKitSynced = false`.

The app is deliberately **write-only** to Apple Health (never requests read access), which preserves the iCloud-storage exemption and — critically for Feature B — means `HKHealthStore.authorizationStatus(for:)` returns the *real* per-type **share** status (read status is the only thing HealthKit hides).

### HealthKit constraints that shape Feature B

1. **Partial permission is detectable.** Because we only share, per-type share authorization is queryable.
2. **A denied type already fails the write.** `HKHealthStore.save()` returns an error for a denied type, so those rows correctly stay unsynced today. No data is lost; it just never reached Apple Health.
3. **The app cannot re-prompt.** Once the user decides (grant/deny) for a type, `requestAuthorization` is a no-op. To add missing permissions the user must toggle them in **iOS Settings → (PillDaddy) → Health**. HealthKit fires **no callback** when they do — the app learns of the change by re-checking status when it next becomes active.
4. **No public deep-link to the per-app Health permission sub-page.** `UIApplication.openSettingsURLString` opens PillDaddy's settings pane, which contains a **Health** row → the per-type toggles. This is the same path the existing Notifications row uses.

---

## Feature A — Capture-screen navigation push

### Problem

`HealthView` presents the metric picker and the capture screen as **two separate sheets**. Tapping a metric calls `dismiss()` on the picker and *then* sets the capture route, producing two modal animations: the picker slides down, a beat passes, then the capture screen slides up. It feels disconnected.

### Desired behavior

A single sheet with a navigation **push**: tap **+** → picker list slides up; tap a metric → the capture screen pushes in from the right while the list slides off-stage left. Selection is **committal** — there is no back-to-picker. Both **Cancel** and **Save** on the capture screen close the entire sheet.

### Design

- **`MetricCaptureRoute`** becomes `Hashable` (for `NavigationLink(value:)` / `navigationDestination(for:)`).
- A small **`AddMetricFlow`** container owns the `NavigationStack`, the sheet's `dismiss`, a root **Cancel**, and a `.navigationDestination(for: MetricCaptureRoute.self)` that builds the capture views, passing the writer and an `onClose: () -> Void` closure (which captures the flow container's `dismiss`).
- The **picker list** rows become `NavigationLink(value: route)` instead of button + callback.
- **`ScalarCaptureView` / `VitalsCaptureView`**:
  - Drop their own inner `NavigationStack` (the container now provides one; nesting would break navigation).
  - Gain `onClose: () -> Void`; both Cancel and post-Save call `onClose()` instead of their own `dismiss()`.
  - Add `.navigationBarBackButtonHidden(true)` so there is no back chevron (committal selection).
  - Wrap their `#Preview`s in a `NavigationStack`.
- **`HealthView`** collapses its two sheets (`showPicker` + `route`) into one `showAdd` sheet presenting `AddMetricFlow`. The delete sheet is untouched.

**Why `onClose` rather than `@Environment(\.dismiss)`:** once a view is pushed onto a `NavigationStack`, its own `dismiss` *pops the stack* (back to the picker) rather than closing the sheet. The closure captured from the flow container reliably closes the whole sheet.

### Files

- `PillDaddy/Views/Health/MetricPickerSheet.swift` (route `Hashable`, add `AddMetricFlow`, rows → `NavigationLink`)
- `PillDaddy/Views/Health/ScalarCaptureView.swift`
- `PillDaddy/Views/Health/VitalsCaptureView.swift`
- `PillDaddy/Views/Health/HealthView.swift`

No files are added or removed, so no `xcodegen generate` is required for Feature A. Verification is build + manual smoke (no view tests in this project).

---

## Feature B — HealthKit authorization visibility & retroactive sync

### 1. Per-type authorization status (writer + protocol)

- New enum `HealthShareAuthorization { case authorized, denied, notDetermined }`.
- Extend `HealthKitWriting`:
  ```swift
  func authorizationStatus(for kind: MetricKind) -> HealthShareAuthorization
  ```
- `LiveHealthKitWriter` maps each `MetricKind` → its HK share type(s) (Blood Pressure = systolic **and** diastolic) and calls `store.authorizationStatus(for:)`, aggregating:
  - `.authorized` only if **all** underlying types are authorized,
  - `.denied` if **any** underlying type is denied,
  - otherwise `.notDetermined`.
- `FakeHealthKitWriter` gains a settable `authorizationByKind: [MetricKind: HealthShareAuthorization]` (default: all `.authorized`) so the service is unit-testable for partial grants.

### 2. Sync + status logic (added to `HealthMetricService`)

- `pendingCount(in:) -> Int` — count of rows with `healthKitSynced == false`.
- `overallAuthorization(writer:) -> HealthAuthState` where `HealthAuthState` is `unavailable | notDetermined | authorized | partial | denied`:
  - `unavailable` when HealthKit isn't available on the device;
  - `authorized` when every kind is `.authorized`;
  - `denied` when every kind is `.denied`;
  - `notDetermined` when every kind is `.notDetermined`;
  - `partial` for any mix.
- `resyncPending(writer:in:) async -> Int` — fetches unsynced rows; for each whose kind's authorization is **already** `.authorized`, maps via `HealthSampleMapper`, saves, marks `healthKitSynced = true`, stores the sample UUID; returns the count newly synced.
  - Does **not** call `requestAuthorizationIfNeeded` — no prompt side-effects on foreground; it only writes already-authorized kinds.
  - Creates **no duplicates**: these rows were never written to Apple Health before.
  - Re-running with nothing newly authorized returns `0` and changes nothing (idempotent).

### 3. `HealthSyncStatusView` (reusable disclosure)

One view, used in two presentation contexts (pushed from Settings; presented as a sheet from the Health tab). Contents:

- **Overall-state header** reflecting `overallAuthorization`, color-cued: Full access (green) / Partial access (orange) / Not enabled / Not available.
- **Per-metric list**: each `MetricKind` with its status — Authorized (✓, green) / Not shared (slash, orange) / Not set (gray).
- **Pending line**: "N readings waiting to sync to Apple Health" (hidden when 0).
- **Sync to Health** button: runs `resyncPending`, then shows a brief result ("Synced N readings" / "Nothing to sync"); disabled when nothing is pending.
- **Open iOS Settings** button: opens `UIApplication.openSettingsURLString` (mirrors the existing Notifications permission row in `SettingsView`).

Takes the writer and uses `@Environment(\.modelContext)`.

### 4. Health tab indicator (`HealthView`)

- Swap the row's `icloud.slash` → `heart.slash` (the gap is Apple Health, not iCloud). Keep the accessibility label ("Not synced to Apple Health").
- Make the indicator a `Button` that presents `HealthSyncStatusView` as a sheet (`@State private var showSyncStatus`).

### 5. Settings entry (`SettingsView`)

- Add an **"Apple Health"** section with a `NavigationLink` to `HealthSyncStatusView`, optionally with a compact status label mirroring the Notifications row. `SettingsView` constructs a `LiveHealthKitWriter()`.

### 6. Auto catch-up on foreground (`PillDaddyApp`)

- Alongside the existing `.onChange(of: scenePhase) { if phase == .active { syncReminders() } }`, add a `syncHealthMetrics()` that calls `HealthMetricService.resyncPending(writer:in:)` against `container.mainContext`. This runs on every return to foreground — including right after the user flips a permission in Settings — independent of the active tab.

### 7. Capture-screen permission notice (capture screens only)

When a capture screen is showing a metric whose authorization is **not** `.authorized`, surface a compact contextual notice inline so the user knows the reading won't reach Apple Health and can fix it before (or after) saving. This applies to the **capture screens only** — the Health tab list keeps the prior design (a tappable per-row indicator that opens `HealthSyncStatusView` as a sheet; see §4).

- New reusable view **`HealthPermissionNotice`**:
  ```swift
  struct HealthPermissionNotice: View {
      let kind: MetricKind
      let writer: HealthKitWriting
      // ...
  }
  ```
  - Renders nothing when `writer.authorizationStatus(for: kind) == .authorized` or when HealthKit is unavailable.
  - Otherwise shows a compact, color-cued notice: "{displayName} won't be saved to Apple Health", an **Open Settings** button (`UIApplication.openSettingsURLString`), and a small **Details** link that presents the full `HealthSyncStatusView` as a sheet.
  - Reads status into `@State` on `onAppear` and refreshes it when `scenePhase` becomes `.active`, so the notice disappears live if the user grants permission and returns. (Default the state to `.authorized` so the notice never flashes before status is determined.)
- **`ScalarCaptureView`** embeds one `HealthPermissionNotice(kind: kind, writer: writer)` (its single metric).
- **`VitalsCaptureView`** embeds a `HealthPermissionNotice` inside each metric's section — `.bloodPressure`, `.pulse`, `.oxygenSaturation` — so the notice is scoped per field (each can have a different status).

Note: `ScalarCaptureView` and `VitalsCaptureView` are **also** modified by Feature A (navigation push). The plan sequences both edits to these two files together to avoid churn.

### Files

- Modify: `PillDaddy/Services/HealthKitWriting.swift` (enum + protocol method + live impl)
- Modify: `PillDaddyTests/HealthKitTestSupport.swift` (fake gains `authorizationByKind` + status method)
- Modify: `PillDaddy/Services/HealthMetricService.swift` (`pendingCount`, `overallAuthorization`, `resyncPending`)
- Create: `PillDaddy/Views/Health/HealthSyncStatusView.swift`
- Create: `PillDaddy/Views/Health/HealthPermissionNotice.swift` (capture-screen inline notice, §7)
- Modify: `PillDaddy/Views/Health/HealthView.swift` (indicator → tappable sheet; symbol swap)
- Modify: `PillDaddy/Views/Health/ScalarCaptureView.swift` (embed notice; also Feature A)
- Modify: `PillDaddy/Views/Health/VitalsCaptureView.swift` (embed per-field notices; also Feature A)
- Modify: `PillDaddy/Views/Settings/SettingsView.swift` (Apple Health section)
- Modify: `PillDaddy/PillDaddyApp.swift` (foreground resync)
- Create: `PillDaddyTests/HealthMetricSyncTests.swift` (resync + overallAuthorization)

Adding `HealthSyncStatusView.swift`, `HealthPermissionNotice.swift`, and the new test file requires `xcodegen generate` before building.

### Testing (Feature B)

Unit tests via `FakeHealthKitWriter.authorizationByKind`:

- `resyncPending` syncs only authorized kinds; denied/notDetermined kinds stay pending.
- `resyncPending` returns the correct newly-synced count and is idempotent on re-run.
- `resyncPending` never duplicates already-synced rows.
- `overallAuthorization` maps summaries → `authorized` / `partial` / `denied` / `notDetermined` correctly.

View changes (`HealthSyncStatusView`, indicator, Settings section, foreground hook) verified by build + manual smoke.

---

## Out of scope (deferred)

- Background sync without foregrounding the app.
- Deleting/updating samples already written to Apple Health (the app is write-only and cannot remove Health data — already disclosed in `DeleteMetricSheet`).
- Per-row retry UI distinct from the centralized "Sync to Health" action.
- A Health-tab banner for partial-permission state (explicitly decided against; recovery lives in Settings + the tappable indicator).
