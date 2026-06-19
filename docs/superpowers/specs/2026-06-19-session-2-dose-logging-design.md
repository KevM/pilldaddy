# Session 2 — Dose Logging

**Date:** 2026-06-19
**Status:** Approved design. Next step: writing-plans → implementation.
**Part of:** [PillDaddy Build Roadmap](2026-06-19-pilldaddy-roadmap.md)
**Depends on:** [Session 1 — Medication & Regime](2026-06-19-session-1-medication-regime-design.md)

## Goal

Turn the stubbed **Today** tab into a working dose-logging checklist that writes `DoseLog` rows.
A caregiver records what was taken, what was deliberately skipped, and at what time — batch-first,
with per-med precision when needed, plus ad-hoc logging for as-needed (PRN) meds. This is the core
interaction the rest of the app (reminders, journal, reporting) builds on.

A caregiver does not open this app once a day — they open it **every time a dose is given** (and,
later, every time a metric is taken), often many times a day, frequently while also handling the
person they care for. The screen must therefore be **fast to get into, fast to act on, and fast to
get out of**: launch lands on the right thing to do *now*, the common action is one tap, and the app
never demands attention it doesn't need. See *Design values* below.

No model changes — Session 0's `DoseLog` already fits. Every action this session writes the
`DoseLog` rows that Session 5 (reporting) will read.

### Design values

These shape every UI decision in this session and are how the implementation should resolve
ambiguity:

- **Glanceable.** On launch the Today screen shows, without scrolling or thinking, what is due now
  and what is done — hence the closest-to-now batch auto-expands and everything else stays collapsed.
- **One-tap common path.** The overwhelming case is "they took the whole batch": *Mark all taken*
  with a sensible default time, no required fields. Friction (notes, per-med adjustment, time
  editing) is opt-in and reserved for the exceptions.
- **Quick in, quick out.** Minimize taps and sheets between opening the app and recording a dose.
  Confirmations exist only where a mistake would be costly or silent (skips, overwrites).
- **Stays out of the way.** No nagging, no blocking, no ceremony for routine logging; the tool
  should feel lightweight to a stressed caregiver doing this for the Nth time today.

## Scope (locked)

- The **Today** tab replaces its placeholder with a real logging screen.
- **Day stepper** at the top: today by default; step **back** to past days to back-fill or correct
  forgotten logs; **no future days**.
- **Batch cards**, color-coded, in time order. Collapsed by default showing a status summary. The
  batch **closest to now by clock** auto-expands; this is an **accordion** — only one card is open
  at a time, and tapping a collapsed card opens it and closes the others. **Once the auto-expanded
  due card is marked taken it collapses**, and nothing re-expands automatically.
- **Mark all taken** → a quick confirm sheet with an **editable time (default now)** and an
  **optional note** → writes a `taken` `DoseLog` for the meds being logged (see *Conflict
  resolution* — this is a fill, not an overwrite).
- **Adjust individually…** → per-med **taken / skip**. A **skip requires a note**; a taken note is
  optional.
- **One `DoseLog` per (medication, scheduled slot, day)**. Re-tapping a logged card edits the
  existing rows (status / time / note) or **reverts to unlogged** (deletes them). Never duplicates.
- **As-needed (PRN)** is its own regime-style card, **collapsed until tapped** — the per-drug log
  UI is hidden until the card is expanded. Each PRN drug has a **Log a dose** action → an ad-hoc
  `DoseLog` (no `batchItem`), with an editable time (default now), optional quantity and note,
  **repeatable** any number of times a day; each logged instance is individually deletable. PRN has
  no pending/missed concept (no schedule).
- A batch appears on a given day only if it **recurs that day** (daily always; weekdays → only on
  its configured weekdays).
- Past-due unlogged batches simply display as **"Pending"** — they are **not** persisted as missed.

### Out of scope (deferred)

- **Auto-missed materialization + the grace-window Settings control** → **Session 3**
  (Reminders & Live Activities). The missed *determination* is just date math, but it is coupled to
  the reminder/pester mechanism, so it lands there. Session 2 shows "Pending," nothing more.
- Reminders / local notifications / Live Activities → Session 3.
- Per-med reasoning **timeline** screen → Session 4.
- History / reporting screens → Session 5.
- HealthKit → Session 6.

## Conflict resolution: individual logs vs. "Mark all taken"

A med may be logged individually *before* the caregiver later taps "Mark all taken" on its batch.
The upsert key (below) already guarantees there is never a duplicate row for the same med/slot/day,
but the policy for the **content** of that single row matters: a deliberate skip (which carried a
required note) must never be silently flipped to taken, and an already-taken dose must not be
re-marked.

**"Mark all taken" is a fill operation, not an overwrite.** Its confirm sheet shows every med in
the batch, grouped by current state:

- **Not yet logged** → listed; will be marked `taken`.
- **Already `taken`** → shown as taken and **left untouched** (original `takenAt` / note preserved;
  no second mark).
- **Already `skipped`** → shown **with its note** and a control to **optionally flip it to taken**.
  If the caregiver leaves it, the skip and its note are preserved.

Mechanically: the sheet computes the set of meds to mark taken — *un-logged meds plus any skips the
caregiver explicitly flipped* — and `DoseLogService.logBatchTaken` writes only that set. Already-taken
rows and un-flipped skips are never modified.

## Architecture

Logic kept separate from SwiftUI and unit-tested, mirroring Session 1's `MedicationService` /
`RegimeQuery` split.

### `DoseLogService`

A plain type whose methods take a `ModelContext` and own each multi-step mutation as a single
atomic save. The idempotency / fill / preservation rules live here so they are testable independent
of the UI; views never hand-roll `DoseLog` mutations.

- **`logBatchTaken(batch, on: day, items: [BatchItem], takenAt: Date, note: String?)`**
  Upserts a `taken` `DoseLog` for each `BatchItem` in `items` (the fill set computed by the confirm
  sheet). Meds not in `items` are untouched. Sets the slot key, `takenAt`, optional note, and the
  frozen snapshot fields.
- **`logMed(batchItem, on: day, status: DoseStatus, takenAt: Date?, note: String)`**
  Upserts a single med's row for that slot/day as `taken` or `skipped`. Guards that a `skipped`
  status carries a non-empty note (the "required note" rule; the model carries no DB constraint, per
  Session 0, so the service and UI enforce it).
- **`revert(batchItem:, on: day)`** and **`revertBatch(batch:, on: day)`**
  Delete the `DoseLog` row(s) for that slot/day → back to unlogged.
- **`logPRN(med, takenAt: Date, quantity: Double, note: String?)`**
  Creates a **new** `DoseLog` with `batchItem == nil` (PRN logs are not upserted — each is its own
  dose). Repeatable.
- **`deletePRNLog(_ doseLog:)`** — removes a single PRN instance.

**Upsert key.** A scheduled `DoseLog` is uniquely identified by `medication` + `batchItem` + the
**same calendar day** of `scheduledDate`. `scheduledDate` is set to the calendar day combined with
the batch's clock time (`batch.timeOfDay`), i.e. the slot's datetime on that day. PRN logs are
exempt (always new rows).

**Quantity.** A scheduled log copies `quantity` from its `BatchItem` (e.g. ½ tablet) at write
time; a PRN log takes the quantity passed to `logPRN` (defaulting to the med's usual single dose).

**Snapshot fields.** On every write, `snapshotMedName`, `snapshotStrength`, and
`snapshotBatchColorHex` are frozen from the current med/batch so history is stable when the med is
later renamed, re-dosed, or moved.

### `DayQuery`

A read helper (like `RegimeQuery`). For a given day it returns:

- The batches that **recur that day** (honoring `recurrenceKind` / `weekdays`), each paired with its
  **active, non-PRN** `BatchItem`s and any existing `DoseLog`s for that slot/day, plus a computed
  per-batch **state**: `pending` (none logged), `partial` (some logged), or `taken` (all logged).
  Discontinued meds are excluded.
- The active **PRN** meds with that day's PRN `DoseLog`s.

This is the single source the `TodayView` renders; it keeps the day-assembly + recurrence + state
logic out of the views and under test.

## Views

Under `PillDaddy/Views/Today/`, reusing the existing `Theme`, `Color+Extension`, and `DoseFormat`.

- **`TodayView`** — `NavigationStack` host: the day stepper, an "X of Y batches done" progress line,
  the batch cards, and the PRN card. Owns the accordion's expanded-card state (initialized to the
  closest-to-now batch on today; collapses a card after it is fully logged). Driven by `DayQuery`.
- **`BatchLogCard`** — collapsed summary (name, time, status chip) ↔ expanded (meds list with
  quantities + **Mark all taken** / **Adjust individually…**). A logged batch shows ✓ and the time.
- **`BatchTakenConfirmSheet`** — the fill sheet from *Conflict resolution*: editable time (default
  now), optional note, the grouped med list (un-logged → will be taken; already-taken → preserved;
  skipped → preserved with an optional flip-to-taken control). Confirm → `logBatchTaken` with the
  computed fill set.
- **`IndividualAdjustSheet`** — per-med taken/skip controls; a note field **required when any med is
  skipped**. Save → `logMed` per changed med. Also the path to re-tap-edit or revert a logged med.
- **`PRNCard`** — the regime-style as-needed card, collapsed until tapped; when expanded, lists
  active PRN meds each with **Log a dose** and that day's logged instances (tap an instance to
  delete).
- **`PRNLogSheet`** — editable time (default now), quantity, optional note → `logPRN`.

## Testing & verification

**TDD on `DoseLogService` and `DayQuery`** (pure SwiftData over an in-memory `ModelContext`, using
the existing `ModelTestSupport` / `PillDaddySchema` setup). Tests written first:

- `logBatchTaken` writes one `taken` row per item in the fill set, with the correct slot
  `scheduledDate`, `takenAt`, optional note, and frozen snapshot fields.
- Re-running `logBatchTaken` for the same batch/day **updates, never duplicates** (upsert).
- Fill semantics: a med already `taken` is left untouched (original `takenAt` preserved) when it is
  not in the fill set; a med already `skipped` is untouched unless explicitly included in the fill
  set (the flip-to-taken case).
- `logMed` with `skipped` sets the status and note and **rejects an empty note**; with `taken` the
  note is optional.
- `revert` / `revertBatch` delete the slot/day rows → unlogged.
- `logPRN` creates a `batchItem == nil` row and is repeatable (multiple rows for one med/day);
  `deletePRNLog` removes exactly one.
- `DayQuery` honors weekday recurrence (a weekdays-only batch is absent on excluded days), attaches
  existing logs, computes `pending` / `partial` / `taken`, and excludes discontinued meds.
- Snapshot fields stay frozen when the med is renamed after logging.

Views are not unit-tested; each gets a `#Preview` driven by the in-memory seed. A few sample
`DoseLog`s are added to `SeedData` (DEBUG-gated) so the Today screen shows a realistic mix of
taken / skipped / pending states for dogfooding and previews.

**Session verification (per [`AGENTS.md`](../../../AGENTS.md)):**

- `xcodegen generate` succeeds; `xcodebuild` builds the scheme cleanly; the test bundle passes.
- App launches; the Today tab renders the seeded day with the closest-to-now batch auto-expanded.
- Manual dogfood pass: mark a batch all-taken (editable time + optional note); adjust a batch
  individually with a required-note skip; mark all-taken on a batch that already has an individual
  skip and confirm the skip is shown and preserved (and flippable); log a PRN dose and delete it;
  step back a day to back-fill; re-tap a logged batch to edit and to revert.

## Dogfood state

The core loop: reach for PillDaddy each time a dose is given — many times a day — log it in a tap or
two, and put the phone down. This builds the dose history the journal and reporting sessions depend
on.
