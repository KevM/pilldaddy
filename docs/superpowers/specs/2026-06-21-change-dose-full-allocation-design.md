# Change Dose: Full Routine Allocation (Issue #15)

**Date:** 2026-06-21
**Issue:** [#15 — Medication → Change Dose does not let you add doses to other Routines](https://github.com/KevM/routine-dose-planner/issues/15)

## Problem

The Change Dose sheet lets a caregiver re-allocate a medication's dose across the
routines it is **already** in, but it cannot place a dose on a routine the
medication is not yet related to. The sheet only iterates `medication.routineItems`
([ChangeDoseSheet.swift:39](../../../RoutineDosePlanner/Views/Meds/ChangeDoseSheet.swift)),
so unrelated routines never appear.

### Motivating scenario

When a medication is **fully allocated** (allocated == daily target), there is no
easy way to move a dose onto a routine not already in the mix:

- **"Add to routine…" is disabled when fully allocated** — the detail view greys it
  out once `DoseAllocation.remaining(med) <= 0`
  ([MedicationDetailView.swift:61](../../../RoutineDosePlanner/Views/Meds/MedicationDetailView.swift)),
  because there is no slack for a new membership.
- **"Move to routine" is all-or-nothing** — it relocates an entire membership's
  quantity; it cannot split a dose (e.g. Morning 2 → Morning 1 + Evening 1).

Change Dose is the natural place to rebalance, because it can lower one routine and
raise/add another in a single atomic save, validating the **prospective total after
all edits** so the over-allocation guard is never tripped mid-way.

## Goal

Make Change Dose a full per-routine allocation editor — add a routine by toggling it
on, remove one by toggling it off, change quantities — mirroring the allocation UI
already used in the Add Medication editor, and reuse that UI in both places.

## Non-Goals

- The existing Schedule-section quick actions ("Add to routine…", per-row Move and
  Remove) stay exactly as they are. They remain the fast, reason-free path that logs
  `scheduleChanged`. Change Dose is the heavier "rethink the whole dose (reason
  required)" path that logs `doseChanged`. Two intentional routes are kept.
- No change to PRN behavior (see below).
- No relabeling of the disabled "Add to routine…" button (explicitly out of scope).

## Design

### 1. Extract a shared allocation control

Pull the allocation UI out of `MedicationEditor` into a reusable SwiftUI view,
`RoutineAllocationSection`, embedded inside the host `Form` by both the Add Medication
editor and the Change Dose sheet:

```swift
RoutineAllocationSection(
    routines: [Routine],                          // all routines, sorted as today
    selected: Binding<Set<PersistentIdentifier>>,
    quantities: Binding<[PersistentIdentifier: Double]>,
    target: Double,
    strengthValue: Double,
    strengthUnit: String
)
```

It renders:

- one toggle row per routine (the current `routineAssignRow`: color dot, name,
  time-of-day, toggle),
- a `DoseQuantityField` for quantity when a routine is toggled on,
- the running "X of Y/day allocated (… strength)" summary, shown red when
  `DoseAllocation.isOverTarget` is true.

`MedicationEditor` keeps owning its `selected`/`quantities` `@State` and passes
bindings down. Its add/edit behavior is unchanged — only the rows move into the
shared view.

### 2. Change Dose sheet rewrite

`ChangeDoseSheet` gains:

- `@Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])`
  for all routines (same sort as the editor),
- `selected: Set<PersistentIdentifier>` and `quantities: [PersistentIdentifier: Double]`
  `@State`.

On `onAppear` it pre-populates from the medication's current memberships: every
routine the med is already in is toggled on, with `quantities` seeded to each item's
current quantity (in addition to the existing strength/unit/target seeding).

The body replaces the current `ForEach(medication.routineItems …)` block with
`RoutineAllocationSection`, passing the live edited `strengthValue` / `strengthUnit` /
`target` so the summary reflects the in-progress strength change as it does today. The
"Reason (required)" section and Save gating (reason valid + not over-allocated) stay.

### 3. Service reconciliation

Change `MedicationService.changeDose`'s `newQuantities` parameter from
`[(item: RoutineItem, quantity: Double)]` to the full desired set
`placements: [(routine: Routine, quantity: Double)]`. The method reconciles against
existing memberships in one atomic save:

1. Validate `reason` is present (`requireReason`) — unchanged.
2. Compute the prospective total = sum of `placements` quantities; reject with
   `DoseAllocationError.exceedsDailyTarget` if it exceeds `newDailyDoseTarget`.
3. Capture `oldSummary = doseSummary(med)`.
4. Apply strength/unit/target changes — unchanged.
5. Reconcile memberships:
   - existing `RoutineItem` whose routine **is** in `placements` → update its quantity,
   - existing `RoutineItem` whose routine is **absent** from `placements` → `context.delete` (toggle-off = remove),
   - routine in `placements` with **no** existing item → `context.insert(RoutineItem(...))`.
6. Capture `newSummary = doseSummary(med)` and insert one `MedicationChangeEvent(type: .doseChanged, oldValue: oldSummary, newValue: newSummary, …)`.
7. `try context.save()`.

Because `doseSummary` already lists all memberships sorted by routine name, added and
removed routines appear naturally in the old→new history line — a single
`doseChanged` event still captures the whole change.

`changeDose` is only called from `ChangeDoseSheet` and the test suite, so the
signature change is contained.

### 4. PRN and quick actions

- **PRN medications:** the allocation section stays hidden for PRN (matching
  `MedicationEditor`, which only shows routine assignment when `!isPRN`). Change Dose
  for a PRN med continues to edit strength only. No behavior change.
- **Quick actions:** the Schedule-section "Add to routine…" button and the per-row
  Move/Remove menu actions are left untouched.

### Edge case

Removing the **last** routine via Change Dose is allowed — it leaves the medication
unallocated ("needs attention"), consistent with how Remove-from-routine already
behaves today.

## Testing

Using Swift Testing (`@Test`, `#expect`, `#require`), in `MedicationServiceTests`:

- Update the existing `changeDose` call sites to the new `placements` signature.
- **Add a routine via Change Dose:** med in one routine, `placements` include a second
  routine within target → a new `RoutineItem` exists with the given quantity; one
  `doseChanged` event recorded.
- **Remove a routine via Change Dose:** med in two routines, `placements` omit one →
  that `RoutineItem` is deleted; remaining membership intact.
- **Pure quantity change:** existing behavior preserved.
- **Over-allocation rejected:** `placements` total > target throws
  `DoseAllocationError.exceedsDailyTarget`; no mutation persisted.
- **Reason required:** empty reason throws `MedicationServiceError.reasonRequired`.

`MedicationEditor` add tests are unaffected — `addMedication` is not changed; only the
row rendering moves into the shared view.

## Files Touched

- `RoutineDosePlanner/Views/Meds/RoutineAllocationSection.swift` — new shared view.
- `RoutineDosePlanner/Views/Meds/MedicationEditor.swift` — use the shared view.
- `RoutineDosePlanner/Views/Meds/ChangeDoseSheet.swift` — query routines, pre-populate,
  use shared view, new save path.
- `RoutineDosePlanner/Services/MedicationService.swift` — `changeDose` reconciliation.
- `RoutineDosePlannerTests/MedicationServiceTests.swift` — updated + new cases.

Run `xcodegen generate` after adding the new file, then build/test against the
iPhone 17 simulator per project conventions.
