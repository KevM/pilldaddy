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
| HealthKit sync | **One-way write only, on save** (immediate, best-effort) | Persist locally, then write to Health right away. Simple for MVP. Two-way sync out of scope (per README/roadmap). Grace-window/undo is deferred — see Future work. |
| Health subject | **Assume the app runs on the patient's primary iPhone** | HealthKit is device-local/single-subject: a write lands in the *device owner's* Health record. For MVP we don't detect device role; onboarding (Session 7) instructs the user to install on the patient's own iPhone so writes are correctly the patient's. A caregiver-proxy model is deferred — see Future work. |
| Editing | **Add / view / delete**, no edit | Delete + re-add covers correction. YAGNI. Delete is guarded by a confirmation disclosure (see Deletion). |
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
    var recordedAt: Date = .now                      // when the reading was taken
    var note: String = ""
    var healthKitSynced: Bool = false                // written to Apple Health yet?
    var healthKitSampleUUID: String? = nil           // traceability / dedup
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
  `recordedAt` desc), delete (guarded by a confirmation disclosure — see **Deletion**), and a
  "+" that presents a chooser → Scalar or Vitals.
- **`ScalarCaptureView(kind:)`** — Weight and Water. One numeric field, label/unit from the
  definition, range-validated. On save: one `HealthMetric` persisted locally, then a best-effort
  HealthKit write.
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
- **Write timing (on save):** **persist the `HealthMetric` locally first, always**
  (`healthKitSynced = false`); capture never blocks on Health. Then attempt the HealthKit write
  immediately; on success set `healthKitSynced = true` + `healthKitSampleUUID`. If Health is
  unavailable/denied or the save fails, the row simply stays unsynced (best-effort — no retry
  queue or background sync in the MVP; see Future work).
- **Mapping:**
  | Metric | HealthKit |
  |--------|-----------|
  | Weight | `HKQuantitySample` `bodyMass`, `HKUnit.pound()` |
  | Water | `HKQuantitySample` `dietaryWater`, `HKUnit.fluidOunceUS()` |
  | Pulse | `HKQuantitySample` `heartRate`, count/min |
  | SpO₂ | `HKQuantitySample` `oxygenSaturation`, percent (0–1) |
  | Blood Pressure | `HKCorrelation` `bloodPressure` of `bloodPressureSystolic` + `bloodPressureDiastolic`, `mmHg` |

### Device assumption

HealthKit can only write to the **local device owner's** Health store (device-local,
single-subject; a sample records the writing *app*, never the *person*). For the MVP we don't
detect or gate on device role; we **assume the app is installed on the patient's own primary
iPhone**, so writes correctly become the patient's Health record. Session 7 onboarding states
this requirement plainly. Handling the caregiver-on-a-different-device case is deferred to
Future work.

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
- **Multi-device duplicates.** The MVP assumes a single device (the patient's primary iPhone).
  If the app is also on another same-Apple-ID device, the write happens on whichever device
  performed the save; the CloudKit-synced `healthKitSynced` flag keeps other devices from
  re-writing the same row. A rare race remains (two devices save/sync near-simultaneously);
  accepted for MVP.

## Data flow

```
Capture (Vitals / Scalar)
  → validate against MetricDefinition range(s)
  → insert HealthMetric (healthKitSynced = false)        ← local persist, always
  → HealthKitWriting.write(metric)                       ← best-effort, immediate
       → map(metric) -> HKObject(s)     (pure, tested)
       → store.save(...)               (unavailable/denied/fails → row stays unsynced)
       → on success: healthKitSynced = true, healthKitSampleUUID
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
- **HealthKit unavailable / denied / save failure:** silent to the flow — the row persists with
  `healthKitSynced = false`. A subtle per-row "not synced to Health" indicator surfaces it. No
  automatic retry in the MVP (re-sync is Future work); the user can delete + re-add if needed.

## Testing

- **Registry:** every `MetricKind` has a definition with sane unit/range/HK mapping.
- **Validation:** range checks; BP both-or-neither; rejects out-of-range.
- **Mapping (pure):** `map(HealthMetric)` produces the correct HK type, unit, and value
  (incl. BP → correlation of two samples). No live store needed.
- **Capture → persist → write:** with a fake writer —
  - saving inserts the expected `HealthMetric` row(s) with `healthKitSynced = false`; Vitals
    writes only the present fields.
  - on a successful write the row flips to `healthKitSynced = true` with a `healthKitSampleUUID`.
  - a writer that throws (denied/unavailable) leaves the row persisted and unsynced — capture
    still succeeds.

## Deletion

Deleting a reading is destructive and asymmetric with our write-only model, so it is **guarded
by a confirmation disclosure** rather than a bare swipe-delete:

- Every delete prompts for confirmation (a destructive-action alert).
- When the row was written to Apple Health (`healthKitSynced == true`), the confirmation
  **discloses that the reading will remain in Apple Health** and must be removed there manually
  (Health app). We intentionally do **not** delete from HealthKit — that would require
  read/Share access and break the write-only iCloud exemption (see App Store considerations).
- The delete removes only the local SwiftData/CloudKit `HealthMetric` row. Unsynced rows
  (`healthKitSynced == false` — e.g. a write that failed or was denied) get the same
  confirmation without the Apple Health caveat.

Add a test that the disclosure copy is driven by `healthKitSynced`, and that delete removes the
local row only.

## App Store / TestFlight considerations

HealthKit works normally on TestFlight (distribution builds), and external testers go through
Beta App Review — so review rules can bite at the TestFlight stage.

- **Hard architectural constraint (here, now):** App Review forbids storing HealthKit-*obtained*
  data in iCloud. Our design is exempt **only because it is write-only** — the metrics in
  CloudKit are the user's own in-app entries, never data read back from HealthKit. **We must
  never add read/Share access** (no `NSHealthShareUsageDescription`), or the exemption breaks.
- **Deferred to Session 7 (launch readiness):** privacy-policy URL (provided by the public
  website), App Privacy "nutrition label" questionnaire, medical disclaimer copy, and the
  concrete usage-string wording. These are submission-gating, not code-gating. See the roadmap's
  Session 7 entry.

## Out of scope (this session)

Sleep Quality; editing readings; two-way Health sync; HealthKit read/Share access; automatic
re-sync / background sync of failed writes; charts/reporting (Session 5); onboarding & broader
privacy strings (Session 7). See Future work for the deferred Health-sync ideas.

## Future work (deferred from MVP)

Explicitly *not* built now, to keep the MVP small — but designed-around so they can be added
later without reworking the core:

- **Deferred write + in-app undo.** A grace window (e.g. ~10 min) before committing to Health,
  so a mis-entry deleted in-app never reaches Apple Health. Implementation that survives app
  lifecycle: a declarative "unsynced sweep" gated on a stored timestamp (not a live timer),
  driven by foreground/background triggers and a best-effort `BGAppRefreshTask` (no APNs — see
  [[cloudkit-no-aps-environment]]). This also gives automatic retry of failed/denied writes.
  Note: HealthKit's own background delivery is read-side only and would break the write-only
  iCloud exemption, so it can't be used for outbound writes (see [[healthkit-write-only-icloud-exemption]]).
- **Patient-device gate.** A device-local `isPatientDevice` flag so only the patient's device
  writes to Health, instead of assuming installation placement.
- **Caregiver proxy app.** A companion experience letting a caregiver capture the patient's
  metrics on the *caregiver's own* device and relay them to the patient's device, which performs
  the HealthKit write. This is the real answer to HealthKit being device-local/single-subject
  (see [[healthkit-device-local-patient-gate]]); likely involves cross-Apple-ID sharing
  (CloudKit Sharing) beyond today's single-Apple-ID private-DB model.

## Dogfood state

A working Health tab: enter weight, water, BP, pulse, SpO₂; readings persist, sync via CloudKit,
and — on the patient's iPhone with authorization granted — write straight to Apple Health on
save.
