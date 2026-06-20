# Session 6 — Health Metrics & HealthKit — Design

**Date:** 2026-06-19
**Status:** Draft for review.
**Depends on:** Session 0 (foundation). Independent of Sessions 1–5 — may be built ahead of Session 5.
**Roadmap:** [`2026-06-19-pilldaddy-roadmap.md`](2026-06-19-pilldaddy-roadmap.md) (this design replaces the Session 6 sketch there).

## Goal

Let a caregiver capture a patient's health metrics in the app and write them one-way into
Apple Health. The work is structured so that adding metric types is cheap (a registry entry,
not a new screen), keeping all metrics in a single session.

## Scope decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Metrics | **Weight, Water, Blood Pressure, Pulse, SpO₂** | Sleep Quality **dropped** — subjective, no clean HealthKit mapping. Can be added later as a specialized form without disturbing this core. |
| Model | **One generic `HealthMetric`** with an optional `secondaryValue` | A single table is simplest for SwiftData/CloudKit and for Session 5 reporting. `secondaryValue` exists solely so Blood Pressure (120/80) is one row, not two loose paired rows. |
| Capture surfaces | **Two:** generic *Scalar* + specialized *Vitals* | Five values, but only two capture experiences. |
| HealthKit sync | **One-way write only**, fire-and-forget | Two-way sync explicitly out of scope (per README/roadmap). |
| Editing | **Add / view / delete**, no edit | Delete + re-add covers correction. YAGNI. |
| Units | **US customary** (Weight = lb, Water = fl oz) | BP = mmHg, Pulse = bpm, SpO₂ = % are fixed. HealthKit stores canonical units and converts. Units are a **single seam** (see Localization readiness) so switching to metric later is contained. |
| Location | Existing **Health** tab (Session 0 stub, tag 3) | No new tab; replaces the "Coming soon" placeholder. |

## Architecture

Three layers, each independently understandable and testable:

1. **Model + registry** — what a metric *is*.
2. **Capture UI** — how a reading gets entered.
3. **HealthKit writer** — how a reading reaches Apple Health.

### 1. Model + registry

**`HealthMetric` (SwiftData `@Model`)** — one row per reading. Follows existing model
conventions (all attributes have defaults for CloudKit; enum stored as raw `String`):

```swift
@Model
final class HealthMetric {
    var kind: String = MetricKind.weight.rawValue   // MetricKind raw value
    var value: Double = 0                            // primary (systolic for BP)
    var secondaryValue: Double? = nil                // diastolic for BP; nil otherwise
    var unit: String = ""                            // canonical display unit
    var recordedAt: Date = .now
    var note: String = ""
    var healthKitSynced: Bool = false                // wrote to Apple Health?
    var healthKitSampleUUID: String? = nil           // traceability for later dedup
}
```

**`MetricKind` enum** (added to `PillModelEnums.swift`, raw `String` per convention):
`weight, water, bloodPressure, pulse, oxygenSaturation`.

**`MetricDefinition`** — a plain (non-persisted) value type; one per `MetricKind`, held in a
static registry keyed by kind. Declares everything the UI and the writer need:

```swift
struct MetricDefinition {
    let kind: MetricKind
    let displayName: String          // "Blood Pressure"
    let archetype: MetricArchetype   // .scalar | .paired
    let captureGroup: CaptureGroup   // .scalar | .vitals
    let unit: String                 // "lb", "fl oz", "mmHg", "bpm", "%"
    let secondaryUnit: String?       // "mmHg" for BP; nil otherwise
    let validRange: ClosedRange<Double>
    let secondaryRange: ClosedRange<Double>?
    let healthKit: HealthKitMapping  // how to compose the HK sample(s)
}
```

Adding a future scalar metric = one registry entry, no new screens. This is the "engine" that
makes breadth cheap. Genuinely novel shapes (e.g. Sleep Quality later) get a new
`captureGroup` + form without touching the generic core.

**Localization readiness.** Units appear in exactly one place — the `MetricDefinition` — and
all entry/display goes through a single formatting helper keyed off the definition (e.g.
`MetricFormatter`). No view hard-codes "lb"/"fl oz". Each `HealthMetric` row also stores its
`unit`, so rows are self-describing. Switching the app to metric (or per-locale units) later is
therefore a contained change — swap the definition's display unit and add conversion in the
formatter — with no data migration, since HealthKit already holds canonical values and historic
rows carry their own `unit`. We ship US customary now; we do not build runtime unit selection.

### 2. Capture UI (Health tab)

- **`HealthView`** replaces the placeholder: a list of recent `HealthMetric` rows (sorted by
  `recordedAt` desc), swipe-to-delete, and a "+" that presents a chooser → Scalar or Vitals.
- **`ScalarCaptureView(kind:)`** — Weight and Water. One numeric field, label/unit from the
  definition, range-validated. On save: one `HealthMetric` + HealthKit write.
  Water is additive (each entry is its own reading); Weight is a snapshot. Same form; the
  difference is only how Session 5 reporting aggregates them later.
- **`VitalsCaptureView`** — one screen with four optional fields: systolic, diastolic, pulse,
  SpO₂. You fill what you measured. On save it writes only the present values:
  - systolic **and** diastolic present → one `bloodPressure` `HealthMetric` (`value`=systolic,
    `secondaryValue`=diastolic). Both-or-neither: one without the other is a validation error.
  - pulse present → one `pulse` `HealthMetric`.
  - SpO₂ present → one `oxygenSaturation` `HealthMetric`.

### 3. HealthKit writer

- **`HealthKitWriting` protocol** wrapping the real `HKHealthStore`, so capture flows depend on
  the protocol and tests use a fake. The mapping logic (HealthMetric → sample) is a **pure
  function**, unit-testable without a live store.
- **Authorization:** request write access for the five HK types lazily on the **first capture
  attempt** (not on mere Health-tab browsing). See **Authorization & permissions** below.
- **Write timing:** **persist the `HealthMetric` locally first, always.** Then attempt the HK
  write. If Health is unavailable or authorization denied, the reading is still saved with
  `healthKitSynced = false` — capture never blocks on Health. No retry queue in v1 (a future
  reconcile pass can resync `healthKitSynced == false` rows; noted, not built).
- **Mapping:**
  | Metric | HealthKit |
  |--------|-----------|
  | Weight | `HKQuantitySample` `bodyMass`, `HKUnit.pound()` |
  | Water | `HKQuantitySample` `dietaryWater`, `HKUnit.fluidOunceUS()` |
  | Pulse | `HKQuantitySample` `heartRate`, count/min |
  | SpO₂ | `HKQuantitySample` `oxygenSaturation`, percent (0–1) |
  | Blood Pressure | `HKCorrelation` `bloodPressure` of `bloodPressureSystolic` + `bloodPressureDiastolic`, `mmHg` |

### Authorization & permissions

HealthKit's authorization model has sharp edges. We're **write-only**, which is the simpler
half — but these points must be handled explicitly, not glossed.

- **Project setup (provisioning).** Two pieces, mirroring the earlier CloudKit work:
  - `com.apple.developer.healthkit` (Boolean `true`) added to
    [`PillDaddy/PillDaddy.entitlements`](../../../PillDaddy/PillDaddy.entitlements), and the
    HealthKit capability enabled on the App ID. A wrong capability set breaks device signing —
    same class of pain as the `aps-environment`/Push lesson noted in project memory.
  - `NSHealthUpdateUsageDescription` (write-only; **no** `NSHealthShareUsageDescription`, since we
    don't read) added to the app target's Info via `info.properties` in
    [`project.yml`](../../../project.yml).
  - Broader privacy-string/onboarding polish still stays in Session 7; only the strictly
    required Update string lands now.
- **Availability guard.** Call `HKHealthStore.isHealthDataAvailable()` before touching the
  store; if false (unsupported device), skip the write path entirely — readings still persist
  locally.
- **Write status is visible.** Unlike read access (hidden by HealthKit for privacy),
  share/write types report honest status via `authorizationStatus(for:)`
  (`.notDetermined / .sharingDenied / .sharingAuthorized`). We use this to drive UI state.
- **Prompt shows once.** If the user denies in the system sheet, `requestAuthorization` will not
  re-present it; the only recovery is **Settings → Health → Data Access & Devices → PillDaddy**.
  The denied state surfaces a brief hint pointing there rather than silently failing forever.
- **Per-type granularity.** The sheet lists all five types together and the user may allow some
  and deny others (e.g. Weight yes, SpO₂ no). The per-row best-effort write handles this
  naturally — each sample/correlation succeeds or fails independently and sets its own row's
  `healthKitSynced`.
- **Multi-device duplicates.** `HealthMetric` rows sync via CloudKit, and Apple Health itself
  syncs across the user's devices via iCloud. To avoid two devices writing the same reading, we
  gate writes on the CloudKit-synced `healthKitSynced` flag (and record `healthKitSampleUUID`).
  A rare race remains (both write before sync converges); accepted in v1, with a future
  reconcile pass as the eventual fix.

## Data flow

```
VitalsCaptureView / ScalarCaptureView
  → validate against MetricDefinition range(s)
  → insert HealthMetric into modelContext   (local persist — always)
  → HealthKitWriting.write(metric)           (best-effort)
       → map(metric) -> HKObject(s)          (pure, tested)
       → store.save(...)
       → on success: set healthKitSynced = true, healthKitSampleUUID
```

## Schema migration

Add `HealthMetric.self` to `PillDaddySchema.schema`. Purely additive — SwiftData/CloudKit
handles it without a migration plan (consistent with Session 0's note that `HealthMetric`
defers cleanly).

## Dev seed data (DEBUG)

Extend the existing DEBUG seed (Session 0 convention) with a handful of recent readings across
all five metrics, so the Health tab and capture flows are exercisable without manual entry.
Seeded rows are local-only (`healthKitSynced = false`); seeding does not touch Apple Health.

## Error handling

- **Range validation** in capture, from the definition; inline field errors. BP enforces
  both-or-neither.
- **HealthKit unavailable / denied:** silent to the flow — reading saved locally,
  `healthKitSynced = false`. Optionally a subtle per-row indicator that it hasn't synced.
- **HK save failure:** same as denied — local row stands, unsynced.

## Testing

- **Registry:** every `MetricKind` has a definition with sane unit/range/HK mapping.
- **Validation:** range checks; BP both-or-neither; rejects out-of-range.
- **Mapping (pure):** `map(HealthMetric)` produces the correct HK type, unit, and value
  (incl. BP → correlation of two samples). No live store needed.
- **Capture → persist:** saving inserts the expected `HealthMetric` row(s); Vitals writes only
  the present fields; HK denial still persists locally (fake writer that throws).

## Out of scope (this session)

Sleep Quality; editing readings; two-way Health sync; HK resync/retry queue; charts/reporting
(Session 5); onboarding & broader privacy strings (Session 7).

## Dogfood state

A working Health tab: enter weight, water, BP, pulse, SpO₂; readings persist (and reach Apple
Health on a real device with authorization granted).
