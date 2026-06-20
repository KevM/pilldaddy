# Session 3 — Reminders & Live Activities

**Date:** 2026-06-19
**Status:** Approved design. Next step: writing-plans → implementation.
**Part of:** [PillDaddy Build Roadmap](2026-06-19-pilldaddy-roadmap.md)
**Depends on:** [Session 1 — Medication & Regime](2026-06-19-session-1-medication-regime-design.md),
[Session 2 — Dose Logging](2026-06-19-session-2-dose-logging-design.md)

## Goal

Turn PillDaddy into a tool that prompts on its own. Each batch occurrence gets a scheduled
reminder lifecycle — a heads-up before, an alert at batch time, and follow-ups that "pester"
until the dose is logged — backed by a **Live Activity** that lives on the Lock Screen / Dynamic
Island and grows more insistent the longer a dose is overdue, modeled after PillBuddy. At the end
of the grace window, an un-logged dose is recorded as **missed** (the materialization Session 2
deferred). The result is the full intended daily experience: on-time prompting that escalates
until you log, and an honest record of what was missed.

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| Reminder lifecycle | −15 min heads-up · batch time · +30/+60/+90 follow-ups · stop at grace |
| Grace window | **Single global setting, default 2 h, adjustable.** Drives **both** pester duration and the missed cutoff. |
| Missed | At the grace cutoff, un-logged meds in the batch are written as persisted `missed` `DoseLog`s. |
| Quick actions | **None in-place.** Notification / Live Activity tap **opens the app**, deep-links to **Today**, expands the relevant batch. |
| Settings (v1) | Master reminders on/off · grace-window duration · 15-min heads-up toggle. (No per-batch opt-out.) |
| Permission | Requested on **first app launch**; reminders default **on**. |
| Live Activity escalation | Calm → amber → red with a pulse near the cutoff, plus a live "missed in N min" countdown (mockup option A). |
| Push vs local | **Local-only this session. No APNs, no push entitlement** — preserves device signing (see *Constraint*). |

## Constraint: local-only Live Activities (no push)

Two ActivityKit operations require an APNs push entitlement (`aps-environment`):
**push-to-start** (starting a Live Activity while the app is not running) and **remote updates**
(escalating it from a server while backgrounded). A prior finding on this
project records that adding the **Push capability previously broke device signing** (CloudKit needs
only the remote-notification background mode + CloudKit entitlement).
PillBuddy's "LA appears while the app is closed" behavior almost certainly uses push-to-start;
matching it exactly would mean resolving that signing/provisioning issue and running a push sender.
We deliberately **defer push** to keep device dogfooding working, and accept the local-only
tradeoffs below. Revisit push in a later session if dogfooding shows the gap matters.

What this means in practice:

- **Notifications are the reliable backbone.** `UNUserNotificationCenter` notifications are
  scheduled in advance and fire on time regardless of app state — they carry the guaranteed pester.
- **The Live Activity is a local companion.** It can only be **started/updated while the app is
  foregrounded**. Because this app is opened many times a day (and a notification tap foregrounds
  it), the app **proactively** starts the LA for the due/overdue batch. Once started, the LA
  persists on the Lock Screen for hours even with the app closed.
- **Self-escalation needs no push:** `Text(timerInterval:)` and
  `ProgressView(timerInterval: scheduledDate ... graceEndDate)` self-update on the Lock Screen
  while the app is closed, giving continuous escalation and the live countdown. The **discrete**
  color/icon tiers step only when the app is next foregrounded (it calls `Activity.update`); between
  foregrounds the bar keeps advancing but the discrete color holds. Acceptable given frequent opens.

## Reminder lifecycle

Per batch occurrence on a day the batch recurs:

| Offset from batch time | What fires | Gated by |
|---|---|---|
| −15 min | "Coming up" heads-up notification | heads-up toggle |
| 0 (batch time) | "Due now" notification **+** start/refresh Live Activity | master toggle |
| +30, +60, +90 min | "Still due" follow-up notifications | only those **before** the grace cutoff |
| +grace (default 120 min) | **Stop** LA + notifications; write `missed` `DoseLog`s | — |

Follow-ups are emitted only at offsets strictly less than the grace window, so shortening the grace
setting prunes them automatically (e.g. a 60-min grace yields only the +30 follow-up).

## Architecture

Logic is kept out of SwiftUI and unit-tested, mirroring the Session 1/2
`MedicationService` / `RegimeQuery` / `DoseLogService` / `DayQuery` split. ActivityKit and
`UNUserNotificationCenter` side effects are isolated behind thin layers; all decision logic lives in
pure, testable functions.

### `ReminderSettings`

A small wrapper over `UserDefaults` exposing `remindersEnabled` (default `true`),
`graceMinutes` (default `120`), and `headsUpEnabled` (default `true`). Used by both views **and**
the scheduler so they read one source of truth (not view-local `@AppStorage`). Mutating any value
triggers a reschedule and a Live Activity refresh.

### `ReminderScheduler`

Wraps `UNUserNotificationCenter`. Its core is a **pure planning function**:

```
plan(activeBatches, graceMinutes, headsUpEnabled, masterEnabled, now, horizon) -> [PlannedNotification]
```

where each `PlannedNotification` is `(identifier, fireDate, kind)`. The side-effecting layer that
applies a plan to `UNUserNotificationCenter` is thin.

- **Recurrence-aware:** schedules a batch only on days it recurs (daily / its `weekdays`), reusing
  the Session 2 recurrence logic.
- **Rolling horizon, reconciled on launch/foreground.** iOS caps an app at **64 pending
  notifications**, so the planner schedules a rolling window (today + the next day or two, capped to
  fit 64) and is recomputed each launch rather than scheduling indefinitely.
- **Stable identifiers** encode `batchID + slotDate + kind`, so when a batch is logged the
  scheduler **cancels that slot's remaining follow-ups** precisely. Logging happens in-app
  (foreground), so cancellation is reliable.
- **Master toggle off** → cancels everything. **Heads-up off** → drops the −15 notifications.

### `MissedReconciler` + `DoseLogService.materializeMissed`

A sweep run on app launch/foreground. For each past batch slot **beyond its grace cutoff** that
recurred that day, any med with **no** `DoseLog` for that slot (no `taken`/`skipped`) gets a
persisted `missed` `DoseLog` via `DoseLogService.materializeMissed`.

- Uses the **Session 2 upsert key** (`medication + batchItem + calendar day` of `scheduledDate`),
  so it is **idempotent** — re-running never duplicates and never overwrites a real `taken`/`skipped`
  log. Frozen snapshot fields are set as in Session 2.
- Excludes discontinued meds; PRN is exempt (no schedule).
- Running on app open means `missed` rows simply appear the next time the app launches after a
  cutoff passes — no background execution required. Session 5 reporting reads these rows.

### `LiveActivityController`

Wraps ActivityKit (app target).

- Computes the **focus batch** = the earliest batch *today* within its pester window (batch time →
  grace cutoff) that is **not fully logged**.
- On foreground / after a logging action: focus batch exists and no activity running for it →
  **start**; activity running for it → **update** (`tier` + content); focus batch logged or past
  grace → **end**.
- **One Live Activity at a time** (the most urgent batch) for v1.
- Gated by `remindersEnabled` and `ActivityAuthorizationInfo().areActivitiesEnabled`.
- Sets `widgetURL` to the deep link that opens the batch (see *Routing*).

### `AppRouter`

An `ObservableObject` injected via the environment, holding `pendingFocus: (batchID, day)?`.

- The `UNUserNotificationCenterDelegate` (notification tap) and the app's `onOpenURL`
  (Live Activity `widgetURL`) both **set `pendingFocus`**.
- `MainTabView` observes it → switches to the **Today** tab.
- `TodayView` observes it → sets the day to today and **expands that batch's card** (reusing its
  existing accordion expanded-state), then clears the focus.

Keeping the navigation intent in one observable object avoids scattering routing through views.

### Live Activity UI — `PillDaddyWidgets` (new widget-extension target)

Live Activities must live in a widget extension, not the app target. XcodeGen gains this target;
`xcodegen generate` wires it. The extension contains only the LA UI — **no SwiftData**.

**Shared contract** (one file compiled into both the app and widget targets):

```
PillReminderAttributes: ActivityAttributes
  // static:  batchID, batchName, colorHex, medCount
  ContentState:  scheduledDate, graceEndDate, tier   // tier: calm | overdue | urgent
```

- **Lock Screen view** and **Dynamic Island** (compact / minimal / expanded) render the batch
  (name, color, med count), a self-updating elapsed `Text(timerInterval:)`, a
  `ProgressView(timerInterval: scheduledDate ... graceEndDate)` filling toward the cutoff, and the
  discrete `tier` styling (calm → amber → red + pulse near the end, with a "missed in N min"
  countdown). Mockup option **A**.
- `widgetURL` deep-links to the focus batch.

## App integration (`PillDaddyApp`)

- Request notification authorization on **first launch**; set the `UNUserNotificationCenter`
  delegate.
- On `scenePhase` → active: run `MissedReconciler`, reschedule via `ReminderScheduler`, and refresh
  the Live Activity via `LiveActivityController`.
- `onOpenURL` (Live Activity tap) → set `AppRouter.pendingFocus`.
- `Info.plist`: `NSSupportsLiveActivities = YES`. `project.yml`: add the widget target + ActivityKit;
  **no push entitlement, no `aps-environment`** (preserves device signing).

## Views

- **`SettingsView`** (replaces the placeholder Settings tab) — bound to `ReminderSettings`:
  master reminders on/off (default on); grace-window picker/stepper (default 2 h, range ~30 min–4 h);
  15-min heads-up toggle (default on); a **permission-status row** that, when notifications are
  denied, links to the system Settings (we can't re-prompt). Changing any control reschedules and
  refreshes the LA.
- **`PillReminderLiveActivity`** — the Lock Screen + Dynamic Island UI described above.

## New / changed files

```
PillDaddy/
  Models/        ReminderSettings.swift
  Services/
    ReminderScheduler.swift          // pure planner + thin UNCenter apply layer
    MissedReconciler.swift
    LiveActivityController.swift
    AppRouter.swift
  Views/
    Settings/SettingsView.swift      // replaces placeholder tab
  Shared/
    PillReminderAttributes.swift     // ActivityAttributes — compiled into BOTH targets
PillDaddyWidgets/                    // NEW widget-extension target
    PillDaddyWidgetsBundle.swift
    PillReminderLiveActivity.swift
```

Edits: `DoseLogService` (+`materializeMissed`), `PillDaddyApp` (permission, delegate, scenePhase,
`onOpenURL`), `MainTabView` + `TodayView` (observe `AppRouter`), `project.yml` (widget target,
ActivityKit), `Info.plist` (`NSSupportsLiveActivities`), DEBUG `SeedData` (an overdue batch so the
LA / missed paths are dogfoodable).

## Testing & verification

**TDD on the pure logic** (in-memory `ModelContext`, existing `ModelTestSupport` /
`PillDaddySchema`):

- **`ReminderScheduler` planner:** produces the correct notification set for given
  batches / grace / toggles / `now` / horizon; honors recurrence (a weekday-only batch is absent on
  excluded days); drops the −15 notifications when heads-up is off; emits **no follow-ups at or past
  the grace cutoff**; produces nothing when the master toggle is off; respects the 64 cap; emits
  slot-stable identifiers enabling precise cancellation.
- **`materializeMissed`:** past un-logged slots beyond grace → `missed` rows; **idempotent**
  (re-run produces no duplicates); never overwrites `taken` / `skipped`; excludes discontinued meds;
  PRN exempt; respects recurrence; freezes snapshot fields.
- **Live Activity tier function:** pure `elapsed → calm | overdue | urgent` tested directly.

ActivityKit and `UNUserNotificationCenter` side effects are **not** unit-tested (cannot run in the
test host); all decision logic is extracted into the pure functions above. The Live Activity UI and
`SettingsView` get `#Preview`s.

**Session verification (per [`AGENTS.md`](../../../AGENTS.md)):**

- `xcodegen generate` succeeds with the new widget target; `xcodebuild` builds **app + widget**
  cleanly; the test bundle passes.
- App launches; the first-launch notification permission prompt appears; Settings toggles work and
  trigger a reschedule.
- On-device dogfood pass: heads-up, due, and follow-up notifications fire on schedule; the Live
  Activity appears for an overdue batch and escalates (progress bar + tier + countdown); tapping a
  notification or the Live Activity deep-links to **Today** with the batch expanded; logging a batch
  cancels its remaining follow-ups and ends the Live Activity; leaving a batch un-logged past the
  grace cutoff materializes `missed` rows on the next app open.

## Dogfood state

The full intended daily experience: open PillDaddy (or get prompted), see what's due, and log it —
with on-time prompting that escalates until you act, and an honest `missed` record when a dose slips
past the grace window. This completes the daily loop the journal (Session 4) and reporting
(Session 5) build on.
