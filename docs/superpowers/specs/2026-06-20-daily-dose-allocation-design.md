# Daily Dose Allocation — Design

**Date:** 2026-06-20
**Status:** Approved (pending implementation plan)

## Problem

A medication captures how much is *in* each unit (`Medication.strength`, free text like `"30mg"`) and how many units are taken in each batch (`BatchItem.quantity`), but there is no stored notion of the **prescribed daily total**, and strength is unstructured free text that can't participate in any math. Consequently:

1. Adding a medication never asks how many units per day are intended.
2. Nothing can flag a med whose batch placements don't add up to its intended daily dose.
3. Adding a med to a batch (`BatchEditor`) silently inserts `quantity: 1.0` with no prompt and no upper bound.
4. The per-batch tablet count can only be changed through the guided `ChangeDoseSheet`, and that flow has no awareness of a daily total to validate against.
5. Because `strength` is free text, the app cannot derive a total daily *strength* (e.g. `30mg × 2 = 60mg/day`) for display or sanity.

These reduce to two missing concepts: a **prescribed daily total** (in unit counts) against which the **allocated** amount can be compared, and a **structured strength** so per-med total dosage can be computed and shown.

## Approach

1. Split `Medication.strength` (free text) into structured `strengthValue: Double` + `strengthUnit: String`.
2. Add a stored `dailyDoseTarget: Double` to `Medication`, expressed in **unit counts** (tablets/day) — the unit the caregiver enters and that all validation uses.
3. Derive total **strength** dosage for display only: `strengthValue × count`. Because this is always within a single med (one uniform unit), **no cross-unit conversion is ever needed** — the unit is a label carried along.
4. A single helper (`DoseAllocation`) owns the count comparison and the derived-mg math. The existing `MedicationService` mutation layer enforces the count cap so the "caregiver can't get it wrong" guarantee stays testable. UI surfaces (editors + a caution badge) mirror that logic for live feedback.

### Allocation rule

`allocated(med)` = the sum of `quantity` across **all** of the med's `BatchItem`s, regardless of each batch's recurrence (daily vs. weekdays). The target represents "units on a full dosing day." Per-weekday accounting is intentionally **out of scope**; a med sitting only in a weekday-restricted batch is treated by its raw quantity sum. This is a known simplification.

### Data migration

None. There is a single user with ~5 medications; existing values will be corrected manually in-app after the model change. The only hard constraint is that all code call sites compile. (`Medication.strengthValue` defaults to `0` and `strengthUnit` to `"mg"`, so a lightweight SwiftData migration succeeds; the old free-text `strength` data is simply dropped.)

## Data Model — `Medication.swift`

Replace:

```swift
var strength: String = ""          // free text, e.g. "30mg"
```

with:

```swift
var strengthValue: Double = 0      // amount per unit, e.g. 30
var strengthUnit: String = "mg"    // label only; never converted across units
var dailyDoseTarget: Double = 1    // prescribed units per full dosing day (count)
```

Add a non-persisted computed property for display, replacing every former read of `strength`:

```swift
var strengthDescription: String { "\(DoseFormat.qty(strengthValue)) \(strengthUnit)" }  // "30 mg"
```

- All three new stored properties are additive/replacing with defaults → SwiftData **lightweight migration** succeeds; no migration plan required. (Confirm `PillDaddySchema` versioning during implementation; bump if explicitly versioned.)
- PRN meds ignore `dailyDoseTarget` entirely (no validation, no badge). They still carry a strength.

### Call-site updates (mechanical)

`strength` is read or constructed in: `PRNCard`, `RegimeView`, `AllMedsView`, `ChangeDoseSheet`, `MedicationDetailView`, `MedicationEditor`, `SeedData`, `DoseLogService`, `MedicationService`, and many tests.

- **Reads** (display) → use `strengthDescription`.
- **`DoseLog.snapshotStrength`** stays a `String`; feed it `med.strengthDescription` at capture time (historical snapshots are unaffected by the model split).
- **Constructors / `init`** → take `strengthValue` + `strengthUnit` instead of `strength`. Seed data and tests update accordingly (e.g. `strengthValue: 30, strengthUnit: "mg"`).

## Logic Core — `Services/DoseAllocation.swift`

The single source of truth. No consumer recomputes allocation independently.

```swift
enum DoseAllocation {
    enum Status { case under, full, over }

    static func allocated(_ med: Medication) -> Double          // Σ batchItems.quantity (counts)
    static func remaining(_ med: Medication) -> Double          // max(0, target − allocated)
    static func status(_ med: Medication) -> Status

    static func allocatedStrength(_ med: Medication) -> Double  // strengthValue × allocated
    static func targetStrength(_ med: Medication) -> Double     // strengthValue × dailyDoseTarget

    static func needsAttention(_ med: Medication) -> Bool       // active, non-PRN, status != .full
}
```

- `status`: `.under` when `allocated < target`, `.full` when equal, `.over` when `allocated > target`.
- `.over` should not occur through the UI (the cap prevents it) but is reachable via migrated/legacy data, so it is represented and badged.
- The `*Strength` helpers are derived display values, formatted with the med's `strengthUnit` (e.g. `"30 of 60 mg"`).

## Service-Layer Validation — `MedicationService`

The cap lives in the mutation layer so it is unit-testable and authoritative; the UI mirrors it for live feedback rather than being the only guard. Validation is always in **counts**.

- New error: `DoseAllocationError.exceedsDailyTarget`.
- New `addToBatch(_ med:_ batch:quantity:in:)` — validates `quantity ≤ remaining(med)`, inserts the `BatchItem`. Initial placement requires **no reason**.
- `changeDose(...)` — its strength params become `newStrengthValue` + `newStrengthUnit`; it gains a `newDailyDoseTarget` parameter and a guard: resulting `allocated ≤ newDailyDoseTarget`, else throw. Using the just-edited target lets the caregiver raise the target and re-allocate in one audited pass. Strength, per-batch quantity, and target changes are all recorded in the `doseChanged` event summary (via `doseSummary`, which now uses `strengthDescription`).
- `addMedication(...)` — strength params become `strengthValue` + `strengthUnit`; gains a `dailyDoseTarget` parameter and validates its `placements` sum `≤ dailyDoseTarget`.
- `swap(...)` — `newStrength` param becomes `newStrengthValue` + `newStrengthUnit`.

## Editor & Validation UX

### Reusable input — `DoseQuantityField`

One component used everywhere a tablet count or the daily-dose target is entered (MedicationEditor add, BatchEditor add-prompt, ChangeDoseSheet, and the daily-dose target field). It pairs:

- a **stepper** for quick `0.5` nudges, and
- a **typed decimal field** (numeric keypad) for exact fractions (`0.75`, `1.25`) — the "manual entry of pill ratio" escape hatch for weaning/transition cases.

Manual entry affects **precision only**; the `≤` count cap still applies. Typed values exceeding the cap show an inline note and block Save. This component also collapses the three near-identical stepper implementations that exist today (`MedicationEditor`, `ChangeDoseSheet`, add-mode rows) into one place.

### Strength input

Wherever strength is entered (MedicationEditor add, ChangeDoseSheet, SwapSheet), replace the single free-text field with a **decimal value field + a unit field** (unit is free text, default `"mg"`; no picker / no normalization needed).

### MedicationEditor — Add mode

- New "Doses per day" `DoseQuantityField`, default `1`, shown only for non-PRN. Save disabled when non-PRN and target `≤ 0`.
- Strength value + unit fields (replacing the free-text strength field).
- The existing inline batch-assignment quantity inputs are capped so their running **sum cannot exceed the target**, with a live caption that shows both units: *"1.5 of 2/day allocated (45 of 60 mg)."* Initial placement → no reason.

### MedicationEditor — Edit (details) mode

Unchanged in scope: name, form, notes, PRN. Strength and the daily-dose target are **not** edited here — both are clinical values changed through the audited dose-change flow.

### BatchEditor — "Add medication"

- Replace the immediate `quantity: 1.0` insert with a small quantity prompt using `DoseQuantityField` (default `min(1, remaining)`, capped at `remaining(med)`), then call `MedicationService.addToBatch`.
- Meds already fully allocated (`remaining == 0`) are shown disabled ("Fully allocated") rather than offered for addition.
- Existing item rows become **tappable → open `ChangeDoseSheet`** for that med, so changing a tablet count "during a batch" is reachable from the batch context (audited).

### ChangeDoseSheet — the audited dose editor

- Add a strength value + unit field and a "Doses per day" `DoseQuantityField` at the top, alongside the per-batch quantity inputs.
- Live validation: the sum of per-batch quantities must be `≤` the (possibly just-raised) target. Show a remaining/over caption (in counts and derived mg) and disable Save while over-allocated, in addition to the existing required-reason gate.

## Caution Badge — `DoseAllocationBadge`

A small reusable view (amber `exclamationmark.triangle` + short label), driven entirely by `DoseAllocation.status`:

- `.under` → "Under daily dose"
- `.over` → "Over daily dose"
- one-line caption where space allows, showing both units: *"1 of 2 tablets/day · 30 of 60 mg."*

Surfaced in: `AllMedsView` rows, `RegimeView` rows, and the `MedicationDetailView` header. PRN and discontinued meds never show the badge.

## Testing (Swift Testing)

- **`DoseAllocationTests`** — `allocated` / `remaining` / `status` across under / full / over; fractional quantities; PRN ignored; migration default of `1`; `allocatedStrength` / `targetStrength` derivation (`strengthValue × count`).
- **`MedicationServiceTests`** —
  - `addToBatch` rejects a quantity exceeding `remaining`.
  - `changeDose` rejects a resulting over-allocation.
  - `changeDose` with a raised `newDailyDoseTarget` permits the new allocation.
  - `addMedication` rejects placements summing over the target.
  - Existing tests updated to the new `strengthValue` / `strengthUnit` constructors.

## Out of Scope

- Per-weekday daily-total accounting (weekday-restricted batches use raw quantity sums).
- Cross-unit conversion / normalization (never needed — totals are per-med, single-unit).
- Cap *override* for exceptional regimens — manual entry is precision-only; the count cap always holds.
- Entering the daily-dose target in strength units (caregiver enters counts; mg is derived).
- Data migration of existing free-text strengths (manual fixup; old data dropped).
- Any change to PRN dosing behavior.

## Decisions Captured

- Strength is **structured** (`strengthValue` + `strengthUnit`); unit is a free-text label, never converted.
- Daily target unit = **count of units/day**, matching `BatchItem.quantity`; total strength (mg) is **derived** for display.
- Migration default `dailyDoseTarget = 1`; **required** on every non-PRN med at Add.
- Initial batch placement = **free** (no reason); changing an existing placement's quantity = **audited** via `ChangeDoseSheet`.
- Strength and target changes happen in the **audited** dose-change flow, not plain Edit details.
- Manual entry = **free decimal precision only**; the count cap is always enforced.
- No data migration; one user fixes ~5 meds by hand.
