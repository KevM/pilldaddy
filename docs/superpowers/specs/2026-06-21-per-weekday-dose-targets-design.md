# Per-Weekday Dose Targets — Design

**Date:** 2026-06-21
**Status:** Approved (design)
**Branch:** ux/med-dose-realloc

## Problem

Daily-dose validation cannot express prescriptions whose amount varies by day of
week. Example: a medication taken **1 on Thursday and 2 on Saturday**.

Today the model is per-day flat:

- `Medication.dailyDoseTarget` is a single number — units per "full dosing day"
  ([Medication.swift:9](../../../RoutineDosePlanner/Models/Medication.swift)).
- Each `RoutineItem` carries a `quantity` and belongs to a `Routine` that recurs
  `daily` or on specific `weekdays`.
- `DoseAllocation.allocated()` **sums every routine item's quantity regardless of
  which days the routine fires**, then `isOverTarget` flags it against the single
  `dailyDoseTarget` ([DoseAllocation.swift:11-24](../../../RoutineDosePlanner/Services/DoseAllocation.swift)).

For "1 Thursday, 2 Saturday" you would build a Thursday routine (qty 1) and a
Saturday routine (qty 2). `allocated()` returns 1 + 2 = 3 and compares it to a
single target — yet those routines never fire on the same day. The two are
treated as if they stack. There is no correct `dailyDoseTarget` to enter.

**Root cause:** allocation is summed across all days but validated against a
single-day target.

## Decisions

The validation's purpose is an **accounting check**: the doses scheduled across
routines must reconcile against the prescription (no more, no less). It is *not*
a safety ceiling.

To keep that check working for variable schedules:

1. **Target model — per-weekday.** The prescription target becomes a per-day-of-week
   amount; the accounting check runs per day.
2. **Migration — snapshot the schedule.** Existing meds set each weekday's target to
   whatever is currently scheduled on that day, so nothing is falsely flagged.
3. **Editing UI — progressive disclosure.** Keep the single "Doses per day" field as
   default; a toggle reveals a 7-row weekday editor for the variable case.
4. **Approach A — additive optional array.** Add an optional per-weekday array to
   `Medication`, keeping `dailyDoseTarget` as the uniform value/fallback. This rides
   SwiftData's automatic lightweight migration (adding an optional property) and
   degrades cleanly to today's behavior for uniform meds.

Rejected alternatives:
- **B — replace the scalar with a required `[Double]` of length 7.** Conceptually
  tidier but removing a stored property is a destructive SwiftData change requiring
  a versioned schema + migration plan, with a larger blast radius.
- **C — a separate prescription-schedule entity.** More flexible (cycles, tapers)
  but YAGNI for weekly patterns expressible with 7 numbers.

## Data model

`Medication` gains one stored property; `dailyDoseTarget` keeps its meaning as the
**uniform** per-day target.

```swift
// Medication.swift
var dailyDoseTarget: Double = 1          // uniform per-day target (existing)
var weekdayDoseTargets: [Double]? = nil  // nil = uniform; else 7 values, index = weekday-1 (1=Sun…7=Sat)
```

Derived accessors on `Medication`:

```swift
/// Prescribed target for a given Calendar weekday (1=Sun … 7=Sat).
func target(forWeekday wd: Int) -> Double {
    weekdayDoseTargets?[wd - 1] ?? dailyDoseTarget
}

/// True when the prescription differs across days (drives UI disclosure).
var hasVariableSchedule: Bool { weekdayDoseTargets != nil }
```

Invariants:
- `weekdayDoseTargets`, when non-nil, is always exactly length 7.
- The editor collapses a uniform 7-array back to `nil` + `dailyDoseTarget`, so we
  never carry redundant state.
- `dailyDoseTarget` remains the value shown/edited in the uniform path and the
  fallback for any day without an explicit override.

Weekday indexing follows `Calendar` (1=Sunday…7=Saturday), matching
`DayQuery.recurs` and `Routine.weekdays`.

## Day-aware allocation & accounting

`DoseAllocation` shifts from a single summed total to per-weekday totals.

```swift
/// Total units scheduled on each Calendar weekday (1=Sun…7=Sat), summing every
/// routine item whose routine fires that day. Index = weekday-1.
static func scheduledByWeekday(_ med: Medication) -> [Double] {
    var totals = [Double](repeating: 0, count: 7)
    for item in med.routineItems ?? [] {
        guard let routine = item.routine else { continue }
        for wd in firingWeekdays(of: routine) {   // daily ⇒ 1...7; weekdays ⇒ its list
            totals[wd - 1] += item.quantity
        }
    }
    return totals
}
```

`firingWeekdays(of:)` is a **single shared helper** factored from the recurrence
rule currently inline in `DayQuery.recurs` (daily ⇒ all 7; weekdays ⇒
`routine.weekdays`), so display and accounting can never diverge.

**Status** becomes a per-day reconciliation:
- **over** — any weekday's scheduled total exceeds that day's target,
- **under** — no day is over, but some day is below its target,
- **full** — every day matches its target (within `tolerance`).

```swift
static func status(_ med: Medication) -> Status {
    let scheduled = scheduledByWeekday(med)
    var anyUnder = false
    for wd in 1...7 {
        let t = med.target(forWeekday: wd)
        if isOverTarget(allocated: scheduled[wd - 1], target: t) { return .over }
        if scheduled[wd - 1] < t - tolerance { anyUnder = true }
    }
    return anyUnder ? .under : .full
}
```

**Capacity for adding to a routine** is now routine-specific, since it depends on
which days that routine fires:

```swift
/// Max additional quantity addable to `routine` without pushing any of its
/// firing days over target. Min slack across the days the routine fires.
static func remaining(_ med: Medication, addingTo routine: Routine) -> Double {
    let scheduled = scheduledByWeekday(med)
    return firingWeekdays(of: routine)
        .map { max(0, med.target(forWeekday: $0) - scheduled[$0 - 1]) }
        .min() ?? 0
}
```

The scalar `allocated(_:)` / `remaining(_:)` forms are removed; all call sites
move to the day-aware versions. Strength helpers (`allocatedStrength`,
`targetStrength`) become per-day / weekly variants as needed by captions.

## Migration

A new idempotent startup migration alongside `DoseLogMigration`, invoked from
[RoutineDosePlannerApp.swift:53](../../../RoutineDosePlanner/RoutineDosePlannerApp.swift),
guarded by a `UserDefaults` flag with a single save:

```swift
// WeekdayTargetMigration.backfill(in:)
for med in allMedications where !med.isPRN && med.weekdayDoseTargets == nil {
    let scheduled = DoseAllocation.scheduledByWeekday(med)
    // Only materialize when the schedule isn't already uniform == dailyDoseTarget.
    if scheduled.contains(where: { abs($0 - med.dailyDoseTarget) > tolerance }) {
        med.weekdayDoseTargets = scheduled        // snapshot, preserves "full"
    }
}
```

- A plain daily med (1.5 every day) stays `nil` (uniform).
- A Mon–Fri med snapshots to `[0, 1.5, 1.5, 1.5, 1.5, 1.5, 0]` and stays "full."
- The schema change itself (adding the optional array) is handled by SwiftData's
  automatic lightweight migration — no versioned schema needed.

## Validation call sites

All flip from a summed check to the day-aware status; each call stays small.

- **`MedicationService.addMedication`** — reject if the prospective med + placements
  would make `DoseAllocation.status == .over`. Replaces the `total > dailyDoseTarget`
  check at [MedicationService.swift:36-39](../../../RoutineDosePlanner/Services/MedicationService.swift).
- **`MedicationService.changeDose`** — after applying prospective placements + targets,
  reject if any day is over. Replaces
  [MedicationService.swift:72-75](../../../RoutineDosePlanner/Services/MedicationService.swift).
- **`MedicationService.addToRoutine`** — reject if `quantity > remaining(med, addingTo:
  routine)`. Replaces [MedicationService.swift:118](../../../RoutineDosePlanner/Services/MedicationService.swift).
- **`moveToRoutine`** — no longer safe to skip the cap check: moving an item between
  routines changes which days it lands on. Must re-check the destination routine's
  days. (A correctness fix the per-weekday model surfaces.)

`DoseAllocationError.exceedsDailyTarget` and its user-facing message stay (wording
tweaked to name the offending day when relevant).

## UI

### 1. Editing — progressive disclosure (`ChangeDoseSheet`, `MedicationEditor`)

Default to the single "Doses per day" field. Add a toggle **"Amount varies by day
of week."**

- **Off (uniform):** one field bound to `dailyDoseTarget`; `weekdayDoseTargets` is
  `nil`.
- **On (variable):** reveals a 7-row Sun→Sat editor (each a `DoseQuantityField`/
  stepper), prefilled from current per-day targets (or `dailyDoseTarget` across all
  rows when coming from uniform).
- **On save:** if all 7 rows are equal, collapse back to `nil` + set
  `dailyDoseTarget`; otherwise store the 7-array. Toggling off reverts to the single
  field showing `dailyDoseTarget`.

### 2. Always communicate the target — `MedicationDetailView`

Today the detail view shows only a mismatch-only badge (renders nothing when
"full"), so a fully-allocated med states neither its target nor which days it
fires. Replace `DoseAllocationBadge` with a `DoseSummaryRow` that:

- **always** renders the target summary:
  - uniform → `1.5 tablets/day · 45 mg/day`
  - variable → a compact per-day line listing only dosing days, e.g.
    `Thu 1 · Sat 2 · 3 tablets/wk`
- shows the under/over caption beneath it only when `status != .full`, naming the
  offending day(s) in the variable case (e.g. `Saturday: 2 of 1 tablet`).

### 3. Show which days each routine fires — Schedule section

Each routine row appends its recurrence when not daily (e.g. `Saturday`,
`Mon–Fri`) using the shared `firingWeekdays` helper, so the per-day picture is
legible at a glance.

### 4. Capacity captions

- `AddToRoutineSheet`: once a routine is selected, the "remaining" caption and the
  `DoseQuantityField` `max` use `remaining(med, addingTo: selectedRoutine)`, reading
  per the selected routine's days (e.g. `1 of 2 remaining on Saturday`). The
  "Add to routine" button in `MedicationDetailView` enables when any routine still
  has slack.
- `RoutineEditor`'s inline remaining caption
  ([RoutineEditor.swift:111](../../../RoutineDosePlanner/Views/Meds/RoutineEditor.swift))
  switches to the routine-aware remaining for the routine being edited.

## Testing

Swift Testing (`@Suite`/`@Test`/`#expect`), matching existing `DoseAllocation` tests.

**`DoseAllocation` (day-aware core)**
- `scheduledByWeekday`: daily routine contributes to all 7; weekday routine only its
  days; two routines overlapping on one day sum on that day.
- Motivating case: Thu qty 1 + Sat qty 2 with targets Thu=1/Sat=2/else=0 ⇒
  `status == .full` (today reports `.over`).
- `status`: `.over` when any day exceeds; `.under` when a day is below and none over;
  `.full` on exact per-day match within `tolerance`.
- `remaining(_:addingTo:)`: min slack across the routine's firing days; daily routine
  constrained by its tightest day.

**`MedicationService` validation**
- `addToRoutine` rejects a quantity that overflows one firing day; accepts when every
  firing day has slack.
- `changeDose` with a variable target accepts a matching placement set, rejects an
  over-target day.
- `moveToRoutine` rejects/relocates correctly when the destination routine's days
  would exceed target.

**Migration**
- A Mon–Fri med backfills to a per-weekday snapshot and reports `.full` afterward.
- A plain daily med stays `weekdayDoseTargets == nil` and `.full`.
- Idempotent: a second run changes nothing.

**Target accessor**
- `target(forWeekday:)` returns `dailyDoseTarget` when `nil`, the array value
  otherwise; uniform-array input collapses to `nil` on save.

## Scope

**In:** `Medication` model, `DoseAllocation` (day-aware rewrite + shared
`firingWeekdays`), `MedicationService` validation (add/change/addToRoutine/move),
startup migration, `ChangeDoseSheet` + `MedicationEditor` editing UI,
`DoseAllocationBadge` → `DoseSummaryRow`, Schedule-section day labels, capacity
captions.

**Out:** Today-view logging (already weekday-aware via `DayQuery.recurs`), PRN
meds (unaffected), HealthKit, reminders/live activities.
