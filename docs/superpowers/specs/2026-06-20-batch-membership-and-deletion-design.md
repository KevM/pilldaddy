# Batch Membership & Deletion UX — Design

**Date:** 2026-06-20
**Status:** Approved (pending implementation plan)

## Problem

Two gaps in the medication/batch UX, plus a latent data-model fragility surfaced while
designing the fix:

1. **No way to delete a batch.** Batches can be created (`MedsView` add menu) and edited
   (`RegimeView` header → `BatchEditor`), but never removed.
2. **No way to manage a medication's batch membership from its own detail view.**
   `MedicationDetailView` shows a read-only "Taken in" list. A caregiver cannot move a med
   between batches (e.g. Morning → Afternoon), and a med that belongs to no batch (post-add)
   has no affordance to be placed in one. Membership can only be changed batch-by-batch from
   inside `BatchEditor`.
3. **The PRN-vs-scheduled discriminator is implicit.** `DayQuery.prnDoses` classifies a
   `DoseLog` as PRN by `batchItem == nil`. This works today only because `logPRN` is the
   single code path that creates a nil `batchItem`. It is fragile coupling, and it becomes
   *incorrect* once batch deletion can nullify a scheduled (discontinued-med) log's
   `batchItem`.

## Guiding principle

**Dose history is self-contained and does not depend on `Batch`.** Every historical fact a
`DoseLog` needs is already frozen on the log at logging time: `scheduledDate`, `takenAt`,
`quantity`, `snapshotMedName`, `snapshotStrength`/`Value`/`Unit`, and `snapshotBatchColorHex`.
No entity holds a *required* (non-optional) reference to `Batch`; `MedicationChangeEvent` has
no link to `Batch`/`BatchItem` at all (it records schedule context as frozen text). Therefore
a batch can be **hard-deleted** without losing any history — the only thing lost is the live
navigable `DoseLog.batchItem` pointer, which history does not rely on.

This principle is why no soft-delete/archive of batches is needed.

## Approach

Three coordinated parts, all mutations routed through the existing service layer so the
invariants stay in one unit-testable place.

### Part 1 — Membership changes are documented (no reason)

Adding, removing, or moving an *existing* medication's `BatchItem` writes a
`MedicationChangeEvent` of a new type `scheduleChanged`. The human-readable change is frozen
in `oldValue`/`newValue`; `reasoning` is left empty (a reason is **not** required for
membership changes — unlike dose/instructions/swap/discontinue).

| Action | `oldValue` | `newValue` |
|--------|-----------|-----------|
| Add    | `""`      | `"Morning · 1 tablet"` |
| Remove | `"Morning · 1 tablet"` | `""` |
| Move   | `"Morning · 1 tablet"` | `"Afternoon · 1 tablet"` |

The descriptive string format is `"{batch name} · {qty} {form}"` (built by a small private
helper; `qty` via `DoseFormat.qty`).

**All entry points route through `MedicationService`** so events are emitted uniformly:
- `MedicationDetailView`'s new Add / Move / Remove actions.
- `BatchEditor`'s existing "Add medication" menu and swipe-to-delete (today they mutate the
  context directly and write no event — they are migrated to the service methods).

> Initial placement during medication *creation* (`MedicationService.addMedication`) is
> unchanged: it inserts `BatchItem`s directly and emits a single `added` event. It does **not**
> call `addToBatch`, so creation never double-logs a `scheduleChanged`.

#### Service methods (`MedicationService`)

- `addToBatch(_ med:_ batch:quantity:in:)` — *exists.* Add `scheduleChanged` event emission.
  Keeps the existing allocation-cap guard (`DoseAllocation.isOverTarget`).
- `removeFromBatch(_ item:in:)` — **new.** Deletes the `BatchItem`, emits a `scheduleChanged`
  event (`oldValue` set, `newValue` empty) against `item.medication`.
- `moveToBatch(_ item:to batch:in:)` — **new.** Reassigns `item.batch` to the target,
  **preserves `item.quantity` unchanged**, emits one `scheduleChanged` event with the
  old→new batch description. Because the quantity is relocated (not added), the med's total
  allocation is unchanged, so **no cap check is needed**. Throws if the target batch already
  contains this med (a med has at most one membership per batch).

### Part 2 — Gated hard-delete of batches

- `MedicationService.deleteBatch(_ batch:in:)` — **new.** Throws
  `BatchError.hasActiveMedications` if any **active, non-PRN** medication has a `BatchItem` in
  the batch. Otherwise `context.delete(batch)`: the cascade rule on `Batch.items` removes any
  remaining join rows (which can only belong to discontinued meds at this point), and
  `DoseLog.batchItem` nullifies. All dose-log snapshots survive intact.

  ```swift
  enum BatchError: Error, Equatable { case hasActiveMedications }
  ```

- **UI:** a destructive **"Delete batch"** button at the bottom of `BatchEditor`, shown only
  when editing an existing batch. When `activeItems` is non-empty the button is disabled with
  an inline caption: *"Remove the N active medication(s) before deleting."* When enabled, a
  confirmation alert (`"Delete this batch? This can't be undone."`) precedes the delete; on
  success the editor dismisses.

### Part 3 — Membership management UI + hardened PRN flag

#### `MedicationDetailView` — Schedule section

For **active, non-PRN** meds, the read-only "Taken in" section becomes an always-shown
**"Schedule"** section:

- Lists each membership: color dot · batch name · `"{qty} {form}"`.
- Each membership row presents a menu: **Move to another batch…** / **Remove from batch**.
  - *Move* opens a batch picker listing only batches the med is **not** already in; on
    selection calls `moveToBatch`. No quantity prompt (quantity carries over).
  - *Remove* calls `removeFromBatch` immediately (no extra confirmation — it writes a
    reversible event and re-adding is trivial, matching `BatchEditor`'s swipe-delete).
- An **Add to batch…** button, shown when there exists at least one batch the med is not
  already in **and** `DoseAllocation.remaining(med) > 0`. It opens a batch picker, then a
  quantity step (reusing `DoseQuantityField`, capped by `DoseAllocation.remaining`), then
  calls `addToBatch`.

PRN meds keep their current detail layout (no memberships, no Schedule section).

#### `MedChangeType` + lineage rendering

- Add `scheduleChanged` to `MedChangeType` (`PillModelEnums.swift`).
- Add a case to `MedicationLineage.title(for:)` — `"Schedule changed"`. (The switch is
  exhaustive, so the new enum case forces this update.) The existing old→new rendering in
  the timeline row already displays `oldValue`/`newValue`.

#### `DoseLog.isPRN` — explicit, frozen discriminator

- Add `var isPRN: Bool = false` to `DoseLog`, frozen at logging time.
- `DoseLogService.logPRN` sets `isPRN: true`; the scheduled `upsert` path leaves it `false`.
- `DayQuery.prnDoses` filters on `$0.isPRN` instead of `$0.batchItem == nil`. After this,
  log classification no longer depends on the live `batchItem` link, so nullifying it on
  batch deletion is provably harmless.

##### Migration / backfill

SwiftData lightweight migration defaults existing `DoseLog` rows to `isPRN = false`, which
would mis-tag pre-existing PRN logs. A one-time launch backfill sets `isPRN = true` for every
existing `DoseLog` where `batchItem == nil`. (Context: single user with a handful of meds, so
risk and volume are low, but the backfill is included for correctness rather than relying on
manual correction of historical logs.)

## Out of scope

- Soft-delete / archive of batches (the guiding principle makes it unnecessary).
- Changing quantity *during* a move (use the existing "Change dose…" action).
- Requiring a reason for membership changes (explicitly decided against — events document the
  what/when; reason stays empty).
- Per-weekday allocation accounting (already out of scope per the daily-dose-allocation spec).

## Testing (Swift Testing)

Service (`MedicationServiceTests` / `BatchRelationshipTests`):
- `addToBatch` emits a `scheduleChanged` event with empty `oldValue` and the correct
  `newValue`; still enforces the allocation cap.
- `removeFromBatch` deletes the item and emits an event with the correct `oldValue` / empty
  `newValue`.
- `moveToBatch` reassigns the batch, preserves `quantity`, leaves total allocation unchanged,
  emits one old→new event, and throws when the target already contains the med.
- `deleteBatch` throws `hasActiveMedications` when an active non-PRN med is present; succeeds
  when none are; cascades remaining discontinued-med join rows; dose-log snapshots remain
  intact and readable after deletion.

Logging / query:
- `logPRN` sets `isPRN == true`; scheduled `upsert` leaves it `false`.
- `DayQuery.prnDoses` classifies via `isPRN` (including a regression: a scheduled log whose
  `batchItem` has been nullified is **not** treated as PRN).
- Backfill tags legacy `batchItem == nil` logs as `isPRN == true`.
