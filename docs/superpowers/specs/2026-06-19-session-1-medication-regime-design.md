# Session 1 — Medication & Regime

**Date:** 2026-06-19
**Status:** Approved design. Next step: writing-plans → implementation.
**Part of:** [PillDaddy Build Roadmap](2026-06-19-pilldaddy-roadmap.md)
**Depends on:** [Session 0 — Foundation & Data Model](2026-06-19-session-0-foundation-design.md)

## Goal

Deliver the fully working **Meds** tab: create/edit/delete medications, organize them into
color-coded, time-based batches with per-batch quantities, view the regime, and perform guided
lifecycle changes (change dose, change instructions, swap, discontinue, reactivate) that always
capture reasoning. This is the app's first real use — the moment the patient's actual regime can
be loaded and exercised.

No dose *logging* (Session 2) and no journal *timeline* screen (Session 4), but every change in
this session writes the `MedicationChangeEvent` rows those sessions read. The Session 0 schema
already supports everything here — **no model additions**.

## Scope (locked)

- Meds tab landing is a **Regime ⇄ All Meds segmented toggle**.
- Meaningful changes are gated by **explicit guided actions**, never inferred — reasoning is
  impossible to skip.
- A swap **inherits the old drug's schedule by default** (editable), always creates a **new** drug
  (not "pick an existing med"), and **auto-discontinues** the old drug as part of the save.
- A "why?" note is **optional on add**, **required** on dose change, instruction change, swap,
  discontinue, and reactivate.
- Discontinuation **preserves all history**: it marks the med (`isActive=false`,
  `discontinuedAt`), keeps `BatchItem` memberships, and writes a `discontinued` event. Regime
  views exclude inactive meds via predicate. Reactivation flips the flag and the placement returns.
- Out of scope: dose logging, the journal timeline screen, reminders/Live Activities, HealthKit,
  drug lookup, interval ("every 3 days") recurrence.

## Architecture

A testable logic layer kept separate from SwiftUI.

### `MedicationService`

A plain type whose methods take a `ModelContext` and own every multi-step mutation as a single
atomic save. Centralizing the "caregiver can't get it wrong" guarantees here makes them
unit-testable independent of the UI. Views call into it; they never hand-roll mutations.

- **`addMedication(name, strength, form, isPRN, notes, placements:[(batch, qty)], reason?)`**
  Creates the `Medication`, a `BatchItem` per placement, and an `added` event (reason optional).
  PRN meds get no placements.
- **`changeDose(med, newStrength?, newQuantities:[BatchItem: qty], reason)`** — *reason required*.
  Mutates `strength` and/or per-batch `quantity`; records old→new into the event's
  `oldValue`/`newValue`; writes `doseChanged`. Same `Medication`, so history stays continuous and
  existing `DoseLog` snapshots are untouched.
- **`changeInstructions(med, batchItem, newInstructions, reason)`** — *reason required*.
  Updates `instructionsOverride`; writes `instructionsChanged` with old→new.
- **`swap(oldMed, newName, newStrength, newForm, inheritSchedule, reason)`** — *reason required*.
  In one save: create the new `Medication`; if `inheritSchedule`, copy the old med's `BatchItem`s
  (batch + quantity) onto the new med; set `oldMed.successor = newMed`; discontinue the old med
  (`isActive=false`, `discontinuedAt=now`); write a `swapped` event on the old med and an `added`
  event on the new.
- **`discontinue(med, reason)`** — *reason required*. Sets `isActive=false`,
  `discontinuedAt=now`, writes `discontinued`. **Keeps** `BatchItem`s; nothing deleted.
- **`reactivate(med, reason)`** — *reason required*. Sets `isActive=true`, clears
  `discontinuedAt`, writes `reactivated`. Existing memberships reappear in the regime.

A small **regime query helper** returns only active meds grouped by batch (ordered by
`sortOrder`/time) with correct per-batch quantities, plus the active PRN meds.

### Views

Under `PillDaddy/Views/Meds/`, reusing the existing `Theme` and `Color+Extension`:

- **`MedsView`** — `NavigationStack` host with the **Regime ⇄ All Meds** segmented toggle and a
  `+` offering **Add medication** / **Add batch**.
- **`RegimeView`** — active meds grouped under their color batches (colored card per batch:
  name, time, meal relation, recurrence; med rows with quantities), plus a trailing
  **As-needed (PRN)** section. Tap a batch header → `BatchEditor`; tap a med row →
  `MedicationDetailView`.
- **`AllMedsView`** — flat A–Z list with a show/hide-discontinued control; each row shows
  strength + batch memberships (or PRN / Discontinued tag).
- **`MedicationDetailView`** — header (name, strength, form, active/discontinued state),
  **Taken in** (memberships + quantities), a **Why / history** preview of recent change events,
  and an **Actions** list:
  - `Edit details` (no note) — name, form, general notes, PRN toggle. Turning a scheduled med
    into PRN removes its `BatchItem`s (behind a confirmation, since it leaves the regime); turning
    PRN off leaves it unscheduled until placed. Strength is *not* edited here — it goes through
    `Change dose…` so the change is journaled.
  - `Change dose…`, `Change instructions…`, `Swap to another drug…`, `Discontinue…` —
    each note-required and guided.
  - For a discontinued med, Actions collapse to `Reactivate…` + `Edit details`.
- **`MedicationEditor`** — add/edit a med: name, strength, form, PRN toggle, general notes, inline
  batch assignment (checkbox per batch + quantity), and an optional "Why started?" field on add.
- **`BatchEditor`** (the "color manager") — name, color swatch picker, time, meal relation,
  daily/weekdays recurrence, and the batch's pill list with quantities (add/remove meds here too).
  Reachable from a batch header or **Add batch**.
- **Guided-change sheets** — focused flows for change dose / change instructions / swap /
  discontinue / reactivate. **Save is disabled until the reason field is non-empty** — this is
  where the "required note" rule lives (the model carries no DB constraint, per Session 0).

### Hard delete

Available from `AllMedsView` for genuine mistakes, behind a confirmation that names it as
permanent and distinct from discontinue. Cascades `BatchItem`s and `changeEvents`; `DoseLog`s
nullify their link but keep their snapshot fields. Discontinue is the preferred path.

## Key behaviors recap

- **Dose change vs. swap.** A dose change mutates the existing med + writes `doseChanged`; a swap
  creates a new med, links `successor`, discontinues the old, and writes `swapped` — exactly the
  model from Session 0.
- **Instructions** = the per-membership `BatchItem.instructionsOverride`. Meal relation stays a
  `Batch` property edited in `BatchEditor`. `changeDose` and `changeInstructions` are split into
  separate guided actions because they write different event types.
- **Discontinued meds** never lose data and are simply filtered from the active regime by
  `isActive`; reactivation restores them with their prior placement intact.

## Testing & verification

**TDD on `MedicationService`** (pure SwiftData over an in-memory `ModelContext`, using the
existing `ModelTestSupport` / `PillDaddySchema` setup). Tests written first:

- `swap` is atomic and correct: old med discontinued (`isActive=false`, `discontinuedAt` set),
  `successor` linked, new med created, schedule inherited when requested and not when not, both
  events written; an empty reason is rejected.
- `changeDose` mutates the same med, records old→new, writes `doseChanged`, leaves prior `DoseLog`
  snapshots untouched.
- `changeInstructions` updates the correct `BatchItem` and writes `instructionsChanged`.
- `discontinue` keeps `BatchItem`s and writes the event; `reactivate` restores active state and
  the regime helper picks the memberships back up.
- `addMedication` creates the right `BatchItem`s and the `added` event; PRN meds get none.
- The regime query helper returns only active meds grouped by batch with correct quantities,
  excluding discontinued ones.

Views are not unit-tested; each gets a `#Preview` driven by the in-memory seed.

**Session verification (per [`AGENTS.md`](../../../AGENTS.md)):**

- `xcodegen generate` succeeds; `xcodebuild` builds the scheme cleanly; the test bundle passes.
- App launches; the seeded regime renders in `RegimeView`; the Regime ⇄ All Meds toggle works.
- Manual dogfood pass on the four guided flows — add a med, change a dose, swap a drug,
  discontinue + reactivate — confirming each writes its event and the reason gate blocks empty
  saves.

## Dogfood state

First real use: load the patient's actual meds and regime and use the app as a live reference.
