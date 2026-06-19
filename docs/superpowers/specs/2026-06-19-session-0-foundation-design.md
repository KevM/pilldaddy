# Session 0 — Foundation & Data Model

**Date:** 2026-06-19
**Status:** Approved design. Next step: writing-plans → implementation.
**Part of:** [PillDaddy Build Roadmap](2026-06-19-pilldaddy-roadmap.md)

## Goal

Stand up a clean PillDaddy project with a correct, CloudKit-compatible SwiftData schema and an
app skeleton that builds, launches, and proves the schema. No feature UI yet — later sessions
fill in the stubbed tabs. The spike is discarded; only XcodeGen config, `Color+Extension`,
`Theme`, and model *shapes* are salvaged as reference.

## Scope (locked)

- **Single patient** — no `Patient` entity; data is global.
- **Deployment target: iOS 26.0** — latest SwiftData / SwiftUI / ActivityKit, no `@available` guards.
- **Free-text medications** — no external drug lookup; no lookup fields on the model yet.
- **`HealthMetric` deferred to Session 6** — SwiftData/CloudKit allows adding it later additively.
- **Recurrence: daily + specific weekdays** — interval dosing ("every 3 days") is a known deferred gap.

## Data model

SwiftData `@Model` classes. All stored properties are defaulted or optional, all relationships
optional with inverses, no `.unique` attributes, enums stored as `String` raw values — these are
hard CloudKit requirements.

### `Medication`
One drug the patient is on. Strength is per-unit ("30mg"); how *many* units are taken lives on
`BatchItem`, not here.

```
name: String = ""
strength: String = ""          // free text, e.g. "30mg"
form: String = "tablet"        // free text, e.g. "tablet", "capsule", "mL"
generalNotes: String = ""
isActive: Bool = true
isPRN: Bool = false            // as-needed, not on a schedule
createdAt: Date = .now
discontinuedAt: Date? = nil

batchItems: [BatchItem]?       // scheduled memberships (empty for PRN)
doseLogs: [DoseLog]?
changeEvents: [MedicationChangeEvent]?
successor: Medication?         // continuity: the med that replaced this one (swap chain)
```

### `Batch`
A color-coded, scheduled grouping ("Blue @ 9am").

```
name: String = ""
colorHex: String = "#3B82F6"
timeOfDay: Date = .now                  // clock time; date component ignored
mealRelation: String = "none"           // "none" | "withFood" | "beforeFood" | "afterFood"
recurrenceKind: String = "daily"        // "daily" | "weekdays"
weekdays: [Int]? = nil                  // 1–7 when recurrenceKind == "weekdays"
sortOrder: Int = 0

items: [BatchItem]?
```

### `BatchItem`
Join: this medication, in this batch, at this quantity. Lets the same med appear in multiple
batches at different amounts (1 tablet in Blue @ 9am, ½ tablet in Green @ 7pm).

```
quantity: Double = 1.0                  // fractions allowed (0.5)
instructionsOverride: String = ""       // optional per-membership note

medication: Medication?
batch: Batch?
```

### `DoseLog`
The record of an action, **per medication**. Carries frozen snapshot fields so historical
reports stay accurate even if the medication is later renamed, re-dosed, or deleted.

```
scheduledDate: Date = .now              // the day/slot this dose belonged to
takenAt: Date? = nil
status: String = "taken"                // "taken" | "skipped" | "missed"
quantity: Double = 1.0
notes: String = ""

// snapshot (frozen at log time)
snapshotMedName: String = ""
snapshotStrength: String = ""
snapshotBatchColorHex: String = ""

medication: Medication?
batchItem: BatchItem?                   // nil for PRN logs
```

### `MedicationChangeEvent`
The reasoning journal — the feature that keeps a stressed caregiver's context intact.

```
timestamp: Date = .now
eventType: String = "note"
// "added" | "doseChanged" | "instructionsChanged" | "swapped" | "discontinued"
// | "reactivated" | "note"
reasoning: String = ""                  // mandatory in UX for change/swap (not a DB constraint)
oldValue: String = ""                   // e.g. "30mg"  (optional context)
newValue: String = ""                   // e.g. "15mg"

medication: Medication?
```

### Relationship summary

```
Medication 1 ──< BatchItem >── 1 Batch          (many-to-many via BatchItem)
Medication 1 ──< DoseLog
Medication 1 ──< MedicationChangeEvent
Medication 0..1 ──> Medication                  (successor; swap continuity chain)
BatchItem 0..1 ──< DoseLog                       (nil for PRN)
```

## Key behaviors the model encodes

- **Dose change vs. drug swap.** A *dose change* mutates the existing `Medication`/`BatchItem`
  and writes a `doseChanged` event — same drug, history preserved in the journal + dose-log
  snapshots. A *swap* creates a **new** `Medication`, sets `discontinuedAt`/`isActive=false` on
  the old, points `old.successor` at the new, and writes a `swapped` event with the reasoning.
- **Atomic, guided change (UX requirement, built in Session 1).** A swap must be performed in a
  single save: discontinue-old + create-new + link `successor` + write event together, with a
  **required reasoning note**. The flow makes it impossible to leave the old med active or the
  replacement unlinked. Dose/instruction changes likewise require a note. The model supports this
  today; no schema additions needed.
- **Scheduled vs. PRN.** Scheduled meds have `BatchItem`s; PRN meds (`isPRN = true`) have none
  and are logged ad hoc (`DoseLog.batchItem == nil`).
- **"Missed" is derived.** No row is persisted per scheduled slot. A day's expected schedule is
  computed from `Batch` + `BatchItem` + recurrence; `DoseLog` records what happened; the
  taken/not-taken views (Session 5) diff the two. `missed` may be written explicitly.

## Project setup

- **XcodeGen** `project.yml` regenerated for the new file layout; deployment target iOS 26.0.
- **Entitlements:** iCloud + CloudKit container; remote-notifications background mode (for
  CloudKit sync).
- **`ModelContainer`** configured with CloudKit (`ModelConfiguration` with the CloudKit database).
- **`AGENTS.md` rule honored:** `xcodegen generate` then a clean `xcodebuild` must succeed before
  the session is considered done.

## App skeleton

`MainTabView` with stubbed tabs, each a placeholder filled by later sessions:

- **Today** (dose logging — Session 2)
- **Meds** (medication & regime — Session 1)
- **Reports** (Session 5)
- **Health** (metrics — Session 6)
- **Settings**

## Dev seed data

A `DEBUG`-gated (or launch-arg-gated) seeder that loads a realistic test regime so every later
session can be exercised without manual setup — unlike the spike, which seeded unconditionally
into production data. Contents:

- Batches: Blue @ 9:00, Green @ 19:00 (+ a couple of the spike's default colors).
- Meds incl. **Metoprolol 30mg** → 1 tablet in Blue, ½ tablet in Green (the worked example).
- At least one **PRN** med (e.g. an as-needed analgesic).
- A sample `MedicationChangeEvent` history on one med to exercise the journal.

## Out of scope for Session 0

Any feature UI (med editing, logging, reports, reminders), HealthKit, `HealthMetric`, the guided
change flow's UI (Session 1), Live Activities, and drug lookup.

## Verification

- `xcodegen generate` succeeds; `xcodebuild` builds the scheme cleanly.
- App launches to the stubbed `MainTabView` on an iOS 26 simulator.
- In `DEBUG`, the seed regime is present and inspectable; relationships resolve (a med shows its
  batch memberships with correct per-batch quantities).
