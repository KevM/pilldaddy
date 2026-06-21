# Routine rename — design

**Date:** 2026-06-21
**Status:** Approved for planning
**Author:** Kevin Miller (with Claude)

## Summary

Unify the app's ubiquitous language around a single noun, **Routine**. Today the
codebase uses two overlapping terms at two different levels:

- **`Regime`** — a non-persisted umbrella concept ("the active daily regime"): the
  whole set of scheduled medications. Surfaces as the `Regime ⇄ All Meds` toggle,
  `RegimeView`, `RegimeQuery`, and assorted prose.
- **`Batch`** — a persisted `@Model` entity: a named, color-coded group of meds
  taken together at one time of day (e.g. "Morning, 8am, with breakfast").

These read as interchangeable in conversation but are a whole-vs-part pair in code.
We collapse the language to:

- **Routine** — the single timed group (today's `Batch`). "Morning routine."
- **Routines** — the whole program (today's "Regime"); just the plural, no separate entity.
- **Routine item** — a med + quantity that belongs to a routine (today's `BatchItem`).

PRN / "as-needed" is unchanged; it remains outside routines as it is today.

Since we are already breaking the persistent store for the rename (see
*Persistence*), the change also folds in a small set of schema improvements that
would otherwise require a future destructive reset.

## Goals

- Replace `Regime` and `Batch` nomenclature with `Routine` across code, files,
  symbols, and user-facing copy.
- Take the one "free" opportunity (the store reset) to add forward-looking schema
  that supports the in-progress FHIR export work.
- Remove vestigial / write-only schema discovered during review.
- Leave the app fully buildable with the test suite green.

## Non-goals

- No data-preserving migration. Existing dev/test stores are discarded (no real users yet).
- No new features (e.g. drag-to-reorder meds within a routine). Those are additive
  and can be added later with a lightweight migration — no reset required.
- No change to PRN/as-needed terminology, enum-stored-as-`String` patterns,
  `timeOfDay`-as-`Date`, or `weekdays`.

## Persistence approach

`Batch` and `BatchItem` are persisted `@Model` classes. SwiftData derives the
entity name — and, on CloudKit, the record type — from the class name. Renaming the
classes therefore changes the persistent entity names and CloudKit record types.

There is currently **no versioned schema and no migration plan**
(`PillDaddySchema` is a flat `Schema([...])` relying on implicit lightweight
migration), and there are no real users. We take the **destructive reset** path:

- No `VersionedSchema` / `SchemaMigrationPlan` is added.
- After the rename, any existing local store is incompatible and must be cleared by
  **deleting and reinstalling** the app on each simulator/device.
- The CloudKit **development** environment schema is reset.

Operational caveat: `PillDaddyApp` `fatalError`s if the container fails to
initialize (`PillDaddyApp.swift:50`). A stale store will crash on launch until the
app is deleted. We treat "delete & reinstall" as the documented step and do **not**
add auto-wipe fallback code.

### Why "add fields now" is genuinely cleaner

Adding a new optional/defaulted property to an existing populated store is a
*lightweight* migration, but a new `uuid: UUID = UUID()` attribute would get a
single shared default applied to all pre-existing rows rather than a unique value
per row. Because we are resetting now, every row is freshly inserted and its `init`
default runs per-object, giving each a distinct UUID. So adding the identifiers as
part of this reset avoids both a future migration and the shared-default hazard.

## Data model changes

### Renames (entities & relationships)

| Today | New |
|---|---|
| `Batch` (model) | `Routine` |
| `BatchItem` (model) | `RoutineItem` |
| `Medication.batchItems` | `Medication.routineItems` |
| `RoutineItem.batch` (was `BatchItem.batch`) | `RoutineItem.routine` |
| `Routine.items` (was `Batch.items`) | unchanged name (`items`) |
| `DoseLog.batchItem` | `DoseLog.routineItem` |

### Additions

| Entity | New field | Notes |
|---|---|---|
| `Medication` | `uuid: UUID = UUID()` | Stable id; FHIR `Medication` resource. |
| `Medication` | `rxNormCode: String = ""` | RXCUI; empty for now, populated later. FHIR `Medication.code`. |
| `DoseLog` | `uuid: UUID = UUID()` | Stable id; FHIR `MedicationAdministration`. Enables idempotent export, deep-links, CloudKit dedup. |

`RoutineItem` deliberately does **not** get a `uuid`: it is an internal config join
row, never exported as its own FHIR resource and never deep-linked.

### Removals

| Entity | Removed field | Reason |
|---|---|---|
| `Routine` (was `Batch`) | `sortOrder: Int` | Vestigial. Used as the *primary* sort key everywhere but never written (no reorder UI; new routines default to `0`). Only seed data set distinct values, and out of time order — a latent bug. |
| `DoseLog` | `snapshotBatchColorHex: String` | Write-only. Captured at log time but read by no view and no test. Pure decoration; the name/strength snapshots that carry clinical/identifying value are kept. |

### Ordering change

With `sortOrder` removed, routines sort purely by `timeOfDay` with a stable
tiebreaker (`uuid`). Every query that currently does
`[SortDescriptor(\.sortOrder), SortDescriptor(\.timeOfDay)]` becomes
`[SortDescriptor(\.timeOfDay), SortDescriptor(\.uuid)]`.

Affected sort sites (verify exhaustively during implementation):
`TodayView`, `RegimeView`→`RoutinesView`, `MedicationEditor`,
`BatchMembershipSheets`→`RoutineMembershipSheets` (two queries), `RegimeQuery`→`RoutineQuery`,
`IndividualAdjustSheet`, `BatchTakenConfirmSheet`→`RoutineTakenConfirmSheet`,
`BatchLogCard`→`RoutineLogCard`.

### Delete-rule behavior (unchanged, documented for safety)

The rename preserves all cardinalities and delete rules. Deleting a routine does
**not** lose dose history:

- `Routine.items` → `.cascade`: deleting a routine deletes its routine items.
- `RoutineItem.doseLogs` → `.nullify`: deleting a routine item sets
  `DoseLog.routineItem` to `nil` and keeps the `DoseLog`.
- `DoseLog` retains frozen snapshot fields, so history renders without the
  originating routine/medication.

## Symbol & file renames

| Today | New |
|---|---|
| `Batch.swift` | `Routine.swift` |
| `BatchItem.swift` | `RoutineItem.swift` |
| `RegimeQuery` enum / `RegimeQuery.swift` | `RoutineQuery` / `RoutineQuery.swift` |
| `RegimeQuery.BatchGroup` / `activeBatchGroups` | `RoutineGroup` / `activeRoutineGroups` |
| `RegimeView` / `RegimeView.swift` | `RoutinesView` / `RoutinesView.swift` |
| `BatchEditor` / `BatchEditor.swift` | `RoutineEditor` / `RoutineEditor.swift` |
| `BatchMembershipSheets.swift` | `RoutineMembershipSheets.swift` |
| `AddToBatchSheet` / `MoveBatchSheet` | `AddToRoutineSheet` / `MoveRoutineSheet` |
| `BatchLogCard` / `BatchLogCard.swift` | `RoutineLogCard` / `RoutineLogCard.swift` |
| `BatchTakenConfirmSheet` / `.swift` | `RoutineTakenConfirmSheet` / `.swift` |
| `BatchError` (in `MedicationService`) | `RoutineError` |
| `DayQuery.BatchState` / `DayQuery.BatchDay` | `RoutineState` / `RoutineDay` |
| `MedsView` mode `.regime = "Regime"` | `.routines = "Routines"` |
| local vars: `batch`, `batches`, `editingBatch`, `batchDay(s)`, `batchUUID`, etc. | `routine`, `routines`, `editingRoutine`, `routineDay(s)`, `routineUUID` |
| `MedicationService.addToBatch` / `removeFromBatch` / `deleteBatch` (and similar) | `addToRoutine` / `removeFromRoutine` / `deleteRoutine` |
| Live Activity (`PillReminderAttributes`) batch fields + notification id/key strings | routine equivalents (ephemeral) |
| Tests: `BatchRelationshipTests.swift`, `RegimeQueryTests.swift` (+ bodies of all test files) | `RoutineRelationshipTests.swift`, `RoutineQueryTests.swift` |

`PillDaddySchema.schema` updates `Batch.self`/`BatchItem.self` →
`Routine.self`/`RoutineItem.self`.

## User-facing copy

All replacements are sentence-case and follow existing voice.

- Segmented control / mode label: `"Regime"` → `"Routines"`.
- `"Batch"` → `"Routine"`; `"batch"` → `"routine"` (and plurals).
- `"Add batch"` / `"New batch"` → `"Add routine"` / `"New routine"`.
- `"Add to batch…"` / `"Add to batches"` → `"Add to routine…"` / `"Add to routines"`.
- `"Edit batch"` → `"Edit routine"`.
- `"Delete batch"` / `"Delete this batch?"` → `"Delete routine"` / `"Delete this routine?"`.
- `"Pills in this batch"` → `"Pills in this routine"`.
- `"Move to another batch…"` / `"Move to batch"` → `"Move to another routine…"` / `"Move to routine"`.
- `"No batches yet — add one from the Meds tab."` → `"No routines yet — add one from the Meds tab."`.
- `"No other batches to move to."` → `"No other routines to move to."`.
- `"This medication is already in every batch."` / `"…in that batch."` → routine.
- `"Total allocation across batches cannot exceed the daily dose target."` → `"…across routines…"`.
- `"Schedules notifications and a Live Activity for each batch."` → `"…each routine."`.
- `"How long after a batch's time before a dose is marked missed."` → `"…a routine's time…"`.
- `"Converted medication to PRN (cleared scheduled batches)"` → `"…cleared scheduled routines)"`.
- `"Discontinuing removes this medication from the active regime. Its full history is kept."` → `"…from your active routines. …"`.
- `"Reactivating restores this medication to the active regime."` → `"…to your active routines."`.
- `"\(doneCount) of \(batchDays.count) batches done"` → `"…routines done"`.
- `"Adjust \(batchDay.batch.name)"` → interpolation updated to `routineDay.routine.name`.

## Explicitly not changed

- PRN / "as-needed" terminology and model behavior.
- Enums stored as `String` raw values (intentional for CloudKit compatibility).
- `timeOfDay` stored as a full `Date` (only the clock component is meaningful).
- `weekdays: [Int]?` representation.

## Verification

1. `xcodegen generate` (regenerate the project after file renames).
2. Full build for the app + widget + tests.
3. Run the entire test suite on **iPhone 17**
   (`-destination 'platform=iOS Simulator,name=iPhone 17'`). All tests green.
4. Delete-and-reinstall the app on the simulator to clear the stale store, launch,
   confirm seed data loads and the Routines/Today/Meds surfaces render with the new
   copy.
5. Reset the CloudKit development schema (manual, out-of-band).

## Risks

- **Missed identifier strings.** Some "batch" usages are notification identifiers
  and Live Activity attribute keys (`batchUUID`, deep-link id formats). These are
  ephemeral; renaming is cosmetic and they are replaced on the next sync. Implementation
  must still update them for consistency and to avoid stale references.
- **Hidden renamed fields on other entities.** `Medication.batchItems`,
  `DoseLog.batchItem`, `DoseLog.snapshotBatchColorHex`, and `RoutineItem.batch` carry
  "batch" naming but live off the `Batch` type; a type-only find/replace would miss
  them. Enumerated above to prevent that.
- **Container crash on stale store.** Mitigated by the documented delete-and-reinstall
  step; no code fallback added.
