# Water Capture Redesign

**Date:** 2026-06-20
**Status:** Approved design, ready for implementation planning
**Scope:** The water entry path in `ScalarCaptureView` and the water row in `MetricRegistry`. Weight and all vitals are untouched.

## Problem

The current water capture UI ([ScalarCaptureView.swift](../../../PillDaddy/Views/Health/ScalarCaptureView.swift)) is built around quick-add chips that *increment* a running value (`value += amt`), plus a separate "Custom + Add" field that also increments. This has two gaps:

1. **No way to clear** — once you over-tap the chips, you can't reset; you can only keep adding.
2. **No way to enter an exact amount** — the "custom" field adds to the total rather than setting it, so there's no direct "log exactly N oz".

The real usage that exposed this: the caregiver weighs each water-bottle fill and logs a specific measured amount (e.g. 14 oz), one fill at a time, rolling into a daily total. Arbitrary, exact numbers — not the neat 8/12/16 the chips assume.

## Goals

- Enter an exact whole-ounce amount directly and fast.
- Clearing / correcting is trivial.
- Each save = one fill; fills roll up into the day's total (unchanged behavior).
- Keep the UI intuitive with no instructional text.

Whole ounces only — no decimals.

## Design — Option C: stepper + set-presets

The water branch of `ScalarCaptureView` is replaced with:

- **Opens pre-set to a default fill of 16 oz.**
- **The number is the hero and is directly editable** — tapping it brings up the system number pad (whole numbers only).
- **− / + stepper** flanks the number, nudging by 1. Clamped to the metric's plausible range (0–256). − is disabled at the lower bound, + at the upper bound.
- **Presets `8 / 12 / 16 / 20` *set* the value** (tap 16 → value becomes 16, not +16). The preset whose number equals the current value is highlighted as active.
- **The number is colored** green/yellow/red by the cue (see below). No worded status pill.
- **"↑ N oz today"** shows the projected daily total (`todayTotal + value`), as today.
- **Note field** retained, low-emphasis at the bottom.
- **Save** records one fill of the entered amount. Disabled when value ≤ 0 or outside the plausible range.

### Removed

- The additive chip behavior (`value += amt`).
- The separate "Custom + Add" `customAmount` field and its Add button.

Both are superseded by direct typing + set-presets.

## Cue changes

Per the decision that the daily total is the meaningful warning and a single measured fill rarely is:

- **Drop the per-fill cue** (previously `> 32` → caution, `> 64` → alert).
- **Keep only the daily-total cue:** projected `todayTotal + value` `> 100` oz → caution (yellow), `> 135` oz → alert (red), else normal.

`waterCue` simplifies to a single daily-total evaluation:

```swift
private static func waterCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
    let total = (ctx.todayTotal ?? 0) + value
    return total > 135 ? .alert : (total > 100 ? .caution : .normal)
}
```

**Advisory only** — the cue never blocks saving (existing invariant). 100 / 135 oz (~3 L / ~4 L) are honest generic defaults for overhydration risk in the general population.

### Out of scope (noted as future work)

Appropriate "too much water" is patient-specific — many tracked patients are on a prescribed fluid restriction far below the general limit (e.g. 48–64 oz/day), others have none. A **per-patient configurable daily limit** that drives the daily cue is the correct long-term solution but is explicitly **future work**, not part of this change.

## Code shape

- **`MetricDefinition`** — `customAddDefault: Double?` is repurposed/renamed to **`defaultValue: Double?`**, the starting entry value. The only consumer is `ScalarCaptureView`. Water sets `defaultValue: 16`; weight stays `nil` (starts empty/0, unchanged).
- **`MetricRegistry`** — water row: `quickAdd: [8, 12, 16, 20]`, `defaultValue: 16`. `waterCue` simplified as above.
- **`ScalarCaptureView`** — the `if let chips = def.quickAdd` branch is rewritten as the stepper/preset/editable-number UI. `onAppear` seeds `value = def.defaultValue ?? 0`. The `else` (plain `TextField`) branch used by weight is untouched.

### Testability

Extract the pure entry logic out of the SwiftUI view so it gets Swift Testing coverage and the view stays thin. The logic to cover:

- **Stepper clamping** — increment/decrement clamps to the plausible range; no movement past either bound.
- **Preset set** — applying a preset sets the value exactly.
- **Active preset** — a preset is "active" iff it equals the current value.
- **Save gating** — `canSave` is true only when value is in range and > 0.
- **Projected total** — `todayTotal + value`.

Suggested form: a small value-type model (e.g. `WaterEntryModel` holding `value`, `range`, `presets`) with `increment()`, `decrement()`, `setPreset(_:)`, `isActive(_:)`, `canSave`, held by the view in `@State`. Exact API is an implementation detail for the plan; the requirement is that the above logic is unit-tested without instantiating the view.

The simplified `waterCue` thresholds should also have/keep cue tests (existing water cue tests will need updating for the dropped per-fill branch).

## Out of scope

- Weight, blood pressure, pulse, oxygen capture.
- Decimal entry.
- Unit conversion (grams → oz) on the scale side.
- Per-patient configurable daily limit (future work, above).
- Any change to how fills are persisted or summed into the daily total.
