# Daily Dose Allocation — Design

**Date:** 2026-06-20
**Status:** Approved (pending implementation plan)

## Problem

A medication captures how much is *in* each unit (`Medication.strength`, free text like `"30mg"`) and how many units are taken in each batch (`BatchItem.quantity`), but there is no stored notion of the **prescribed daily total**. Consequently:

1. Adding a medication never asks how many units per day are intended.
2. Nothing can flag a med whose batch placements don't add up to its intended daily dose.
3. Adding a med to a batch (`BatchEditor`) silently inserts `quantity: 1.0` with no prompt and no upper bound.
4. The per-batch tablet count can only be changed through the guided `ChangeDoseSheet`, and that flow has no awareness of a daily total to validate against.

All four reduce to one missing concept: a **prescribed daily total** against which the **allocated** amount (sum of `BatchItem.quantity` across the med's batches) can be compared.

## Approach

Add a stored `dailyDoseTarget` to `Medication`. Allocation is never stored — it is always derived as the sum of the med's `BatchItem.quantity` values. A single helper owns the comparison math, and the existing `MedicationService` mutation layer enforces the cap so the "caregiver can't get it wrong" guarantee stays testable. UI surfaces (editors + a caution badge) mirror that logic for live feedback.

### Allocation rule

`allocated(med)` = the sum of `quantity` across **all** of the med's `BatchItem`s, regardless of each batch's recurrence (daily vs. weekdays). The target represents "units on a full dosing day." Per-weekday accounting is intentionally **out of scope**; a med sitting only in a weekday-restricted batch is treated by its raw quantity sum. This is a known simplification.

## Data Model

`Medication.swift` gains:

```swift
var dailyDoseTarget: Double = 1   // prescribed units per full dosing day
```

- Additive, non-optional, default `1` → SwiftData **lightweight migration**, no migration plan required. (Confirm `PillDaddySchema` versioning during implementation; bump the schema version if it is explicitly versioned.)
- Existing/seeded meds migrate to a target of `1`; if their allocation differs they surface via the caution badge.
- PRN meds ignore the target entirely (no validation, no badge).

## Logic Core — `Services/DoseAllocation.swift`

The single source of truth. No consumer recomputes allocation independently.

```swift
enum DoseAllocation {
    enum Status { case under, full, over }

    static func allocated(_ med: Medication) -> Double      // Σ batchItems.quantity, all batches
    static func remaining(_ med: Medication) -> Double      // max(0, target − allocated)
    static func status(_ med: Medication) -> Status
    static func needsAttention(_ med: Medication) -> Bool   // active, non-PRN, status != .full
}
```

- `status`: `.under` when `allocated < target`, `.full` when equal, `.over` when `allocated > target`.
- `.over` should not occur through the UI (the cap prevents it) but is reachable via migrated/legacy data, so it is represented and badged.

## Service-Layer Validation — `MedicationService`

The cap lives in the mutation layer so it is unit-testable and authoritative; the UI mirrors it for live feedback rather than being the only guard.

- New error: `DoseAllocationError.exceedsDailyTarget`.
- New `addToBatch(_ med:_ batch:quantity:in:)` — validates `quantity ≤ remaining(med)`, inserts the `BatchItem`. Initial placement requires **no reason** (it is part of creating the placement). `BatchEditor`'s current inline insert is replaced by this call.
- `changeDose(...)` gains a `newDailyDoseTarget` parameter and a guard: the resulting `allocated` must be `≤ newDailyDoseTarget`, else throw. Using the *just-edited* target means the caregiver can raise the target and re-allocate in a single audited pass. The `dailyDoseTarget` change is recorded in the existing `doseChanged` event summary.
- `addMedication(...)` gains a `dailyDoseTarget` parameter and validates that its `placements` sum `≤ dailyDoseTarget`.

## Editor & Validation UX

### Reusable input — `DoseQuantityField`

One component used everywhere a tablet count or the daily target is entered (MedicationEditor add, BatchEditor add-prompt, ChangeDoseSheet, and the daily-dose target field). It pairs:

- a **stepper** for quick `0.5` nudges, and
- a **typed decimal field** (numeric keypad) for exact fractions (`0.75`, `1.25`) — the "manual entry of pill ratio" escape hatch for weaning/transition cases.

Manual entry affects **precision only**; the `≤` cap still applies. Typed values exceeding the cap show an inline note and block Save. This component also collapses the three near-identical stepper implementations that exist today (`MedicationEditor`, `ChangeDoseSheet`, the add-mode rows) into one place.

### MedicationEditor — Add mode

- New "Doses per day" `DoseQuantityField`, default `1`, shown only for non-PRN meds. Save disabled when non-PRN and target `≤ 0`.
- The existing inline batch-assignment quantity inputs are capped so their running **sum cannot exceed the target**, with a live caption: *"1.5 of 2/day allocated."* Initial placement → no reason.

### MedicationEditor — Edit (details) mode

Unchanged in scope: name, form, notes, PRN. The daily-dose target is **not** edited here — it is a clinical value changed through the audited dose-change flow.

### BatchEditor — "Add medication"

- Replace the immediate `quantity: 1.0` insert with a small quantity prompt using `DoseQuantityField` (default `min(1, remaining)`, capped at `remaining(med)`), then call `MedicationService.addToBatch`.
- Meds already fully allocated (`remaining == 0`) are shown disabled ("Fully allocated") rather than offered for addition.
- Existing item rows become **tappable → open `ChangeDoseSheet`** for that med, so changing a tablet count "during a batch" is reachable from the batch context (audited).

### ChangeDoseSheet — the audited dose editor

- Add a "Doses per day" `DoseQuantityField` at the top, alongside the strength field and the per-batch quantity inputs.
- Live validation: the sum of per-batch quantities must be `≤` the (possibly just-raised) target. Show a remaining/over caption and disable Save while over-allocated, in addition to the existing required-reason gate.
- On save, `changeDose` records the strength, per-batch quantity, and daily-target changes in the audit event.

## Caution Badge — `DoseAllocationBadge`

A small reusable view (amber `exclamationmark.triangle` + short label), driven entirely by `DoseAllocation.status`:

- `.under` → "Under daily dose"
- `.over` → "Over daily dose"
- one-line caption where space allows: *"1 of 2 tablets/day allocated."*

Surfaced in:

- `AllMedsView` rows
- `RegimeView` rows
- `MedicationDetailView` header

PRN and discontinued meds never show the badge.

## Testing (Swift Testing)

- **`DoseAllocationTests`** — `allocated` / `remaining` / `status` across under / full / over; fractional quantities; PRN ignored; migration default of `1`.
- **`MedicationServiceTests`** —
  - `addToBatch` rejects a quantity exceeding `remaining`.
  - `changeDose` rejects a resulting over-allocation.
  - `changeDose` with a raised `newDailyDoseTarget` permits the new allocation.
  - `addMedication` rejects placements summing over the target.

## Out of Scope

- Per-weekday daily-total accounting (weekday-restricted batches use raw quantity sums).
- Cap *override* for exceptional regimens — manual entry is precision-only; the cap always holds.
- Any change to PRN dosing behavior.
- Computing total daily strength (mg) from `strength × target` — `strength` remains free text.

## Decisions Captured

- Daily target unit = **count of units/day**, matching `BatchItem.quantity`.
- Migration default = **1**; **required** on every non-PRN med at Add.
- Initial batch placement = **free** (no reason); changing an existing placement's quantity = **audited** via `ChangeDoseSheet`.
- Target changes happen in the **audited** dose-change flow, not plain Edit details.
- Manual entry = **free decimal precision only**; the `≤ daily dose` cap is always enforced.
