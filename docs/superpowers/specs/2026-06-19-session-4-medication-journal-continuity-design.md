# Session 4 — Medication change journal & continuity

**Date:** 2026-06-19
**Status:** Approved design. Next step: writing-plans → implementation.
**Part of:** [PillDaddy Build Roadmap](2026-06-19-pilldaddy-roadmap.md)
**Depends on:** [Session 1 — Medication & Regime](2026-06-19-session-1-medication-regime-design.md),
[Session 2 — Dose Logging](2026-06-19-session-2-dose-logging-design.md)

## Goal

Make the *why* behind every medication change readable as one continuous story across drug
substitutions. Sessions 0–1 already record a `MedicationChangeEvent` on every mutation
(add / dose / instructions / swap / discontinue / reactivate) and link swapped drugs through a
`successor` / `predecessor` chain. This session turns that latent data into the headline feature: a
**lineage-aware reasoning timeline** that walks the whole successor chain (e.g. Atenolol →
Metoprolol → Bisoprolol) and merges every drug's events into a single chronological narrative, so a
stressed caregiver can see the entire reasoning history of a *therapy line* in one place — not just
the current drug. It also adds the ability to append a **free-form retrospective note**, and ships
the reusable chain-walking primitive that Session 5 reporting will lean on to aggregate doses across
a chain.

There are **no model or schema changes.** Everything is built on the existing `Medication`,
`MedicationChangeEvent`, and `successor` / `predecessor` relationships.

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| Lineage span | **Always the full line.** From any node, show all predecessors + successors as one story, with the anchor (the med you opened from) visually distinguished. |
| Layout | **Single reverse-chronological stream** (newest first), merging every drug's events. No grouping, no lineage header strip. |
| Swap-row labeling | Title reads **"Swapped to {new drug}"** (the event lives on the *old* med; `successor.name` supplies the destination). The `old → new` line underneath carries the strengths. No "from {old}" badge. |
| Redundant `added` | **Suppressed for swap-born drugs.** Show `added` only for the line's **root** (the med with no `predecessor`); a swapped-in drug's origin is already its predecessor's "Swapped to …" row. |
| Attribution tag | Non-anchor rows that are **not** swap rows carry a plain `{drug name}` tag, so a dose/instruction change on an earlier drug is attributable. Anchor rows and swap rows are untagged. |
| Retrospective notes | **In scope.** A free-form note (`MedChangeType.note`) can be appended to the anchor med from the timeline; empty text rejected. |
| Dose-history continuity | **Deferred to Session 5.** This session ships the chain primitive; aggregating `DoseLog`s across the chain is reporting's job. |

## `MedicationLineage` — the continuity primitive

A pure helper (an `enum` namespace, matching the existing service style), placed in `Services/`
next to `RegimeQuery`. No `ModelContext` needed — it traverses the in-memory
`successor` / `predecessor` relationships. Fully unit-testable against constructed chains.

- `ordered(from med: Medication) -> [Medication]` — walk `predecessor` back to the root, then
  `successor` forward to the tip, returning the line **oldest → newest**. **Cycle-guarded:** track
  visited object identities so a malformed link can never infinite-loop.
- `events(from med: Medication) -> [LineageEvent]` — gather `changeEvents` across every drug in the
  line, apply the merge rules below, and return them sorted **newest first**.
- `LineageEvent` — a small value type carrying:
  - the underlying `MedicationChangeEvent`,
  - its owning `Medication`,
  - `isAnchor: Bool` (owning med == the med the timeline was opened from),
  - `successorName: String?` (for swap rows: `owningMed.successor?.name`).

### Merge rules (presentation logic, not data changes)

1. **Drop `added` events whose med has a non-nil `predecessor`.** Only the lineage root keeps its
   "Added" row; swap-born drugs are introduced by the preceding "Swapped to …" row.
2. **Swap rows** render the title `Swapped to {successorName}`. If `successorName` is somehow nil
   (data integrity gap), fall back to the existing generic "Swapped" title.
3. Everything else is included as-is and sorted by `timestamp` descending.

## `MedicationTimelineView` — the screen

A `List`-based screen pushed from `MedicationDetailView`. Renders the merged stream from
`MedicationLineage.events(from:)`.

Each row shows (reusing the detail view's existing `eventTitle` mapping and row content):

- **Title** — e.g. "Note", "Dose changed", "Swapped to Bisoprolol", "Added".
- **Attribution tag** — a small `{drug name}` capsule on non-anchor, non-swap rows only.
- **Reasoning** — `event.reasoning`, secondary text.
- **`old → new` line** — shown only when `oldValue` / `newValue` is non-empty; mono, tertiary.
- **Date** — trailing, `event.timestamp`.
- **Type glyph** — a leading dot/icon encoding the event type (structural change vs. swap vs.
  note). Presentation nicety only; nothing persisted.

Empty state mirrors the detail view's current "No history yet."

### Entry point

`MedicationDetailView`'s existing "Why / history" section keeps its 5-event preview, but:

- The preview's source changes from *this med's* `changeEvents` to `MedicationLineage.events(from:)`
  (so even the preview is lineage-aware), still capped at 5.
- A **"See full history"** navigation row is appended that pushes `MedicationTimelineView(anchor:)`.
  Show it whenever the lineage has more events than the preview displays.

## Retrospective notes

- New `MedicationService.addNote(_ med: Medication, text: String, in context: ModelContext) throws`
  — validates non-empty text by reusing the existing `requireReason` guard (throws
  `MedicationServiceError.reasonRequired` on empty / whitespace-only input), inserts
  `MedicationChangeEvent(type: .note, reasoning: text, medication: med)`, and saves. Atomic single
  save, consistent with the other mutations.
- Entry point: an **"Add note"** affordance on `MedicationTimelineView` (a toolbar `+`). The note
  attaches to the **anchor** med and appears immediately at the top of the stream.

## Testing

- **`MedicationLineageTests`** (new):
  - `ordered(from:)` returns the full line from a *mid-chain* node.
  - A med with no links degenerates to a single-element line.
  - Cycle guard terminates on a malformed `successor` loop.
  - `events(from:)` ordering is correct across multiple drugs.
  - `added` suppression: root keeps "Added"; swap-born drugs do not emit one.
  - `isAnchor` / `successorName` populated correctly.
- **`MedicationServiceTests`** (extend): `addNote` writes a `.note` event with the given text;
  empty / whitespace-only text throws and writes nothing.
- **`#Preview`** for `MedicationTimelineView` against `PreviewSupport.seededContainer()`, matching
  existing view conventions.

## Seed data

The DEBUG seed must contain at least one **swapped chain** (a beta-blocker A → B, ideally A → B → C)
with reasoning on each transition, plus a dose change on an earlier drug and a free-form note, so
the lineage timeline's continuity is exercisable the moment the app launches. If `SeedData` does not
already include such a chain, add one — otherwise the session's headline feature can't be dogfooded.

## Out of scope

- Aggregating `DoseLog` history across the chain (Session 5 — Reporting).
- Editing or deleting existing change events (the journal is append-only).
- Any change to how swaps / dose changes / lifecycle events are *written* (Session 1 owns that).
- Model or CloudKit schema changes.

## Dogfood state

Value compounds as meds change over weeks: each swap and dose change leaves a continuous,
attributable reasoning trail the caregiver can read end-to-end without holding it in their head.
