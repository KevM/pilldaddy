# PillDaddy — Build Roadmap

**Date:** 2026-06-19
**Status:** Approved roadmap. Each session below gets its own brainstorm → spec → plan → implementation cycle.

## Vision

PillDaddy is a caregiver's iOS app for tracking the medications and health metrics of an
(often elderly) person. It organizes medications into color-coded, time-based batches; lets a
caregiver log what was taken and what was missed; captures the *clinical reasoning* behind
medication additions and changes so a stressed caregiver doesn't have to hold it all in their
head; reports on dose history; and records health metrics into Apple Health.

Built with **SwiftUI + SwiftData/CloudKit**, with **one-way sync into Apple Health**.

### Source of truth

The product vision lives in [`README.md`](../../../README.md). This roadmap
extends it with one addition agreed during brainstorming: **capturing medical reasoning on
medication additions and changes is a first-class feature**, because caregivers managing many
medications are often stressed and cannot reliably remember why each change was made.

## Scope decisions

| Decision | Choice | Implication |
|----------|--------|-------------|
| Patient model | **Single patient** | No `Patient` entity; data is global. Simplest model. |
| Reminders | **Active reminders + Live Activities** (PillBuddy-style "pester") | Notifications + ActivityKit subsystem (Session 3). |
| Drug lookup | **Free-text in v1**, structured for later | No external drug API now; model leaves room for it. |
| Distribution | **TestFlight-focused**, decide later | Moderate ceremony; defer App Store polish to Session 7. |
| Deployment target | **iOS 26.0** | Latest SwiftData / SwiftUI / ActivityKit with no `@available` guards. Dogfood devices must be on iOS 26+. |
| Spike code | **Throwaway** | Rebuild clean; salvage XcodeGen config, `Color+Extension`, `Theme`, and model *shapes* as reference only. |

## Approach: vertical spine first

Build the thinnest end-to-end medication loop early (data model → add meds/batches → log a
dose → see it), so the app is **usable and dogfoodable as early as possible**, then layer
reminders, continuity, reporting, and metrics on top. This de-risks the hard pieces (CloudKit
schema, Live Activities) by hitting them on real foundations, and surfaces schema problems early.

Health metrics + HealthKit (Session 6) is a **semi-independent track** that can slot in any time
after the foundation.

### Cross-cutting constraints (apply to every session)

1. **Always runnable.** Every session ends with the app building and launching cleanly (per
   [`AGENTS.md`](../../../AGENTS.md)). No session leaves a half-wired screen or dead navigation.
2. **Dogfoodable with a test patient from Session 1.** Medication data entry lands in Session 1,
   not later, so a real regime can be loaded and exercised the moment medication management exists.
3. **Dev seed data from Session 0**, so each session can be exercised without manual setup.

### CloudKit caveat

CloudKit sync works properly only on a **real device with a signed-in iCloud account**. The
Simulator is unreliable for sync (local SwiftData persistence works fine there). Meaningful
cross-device dogfooding means running on-device via Xcode or TestFlight.

## Sessions

Dependencies are listed per session. Each is its own brainstorm → spec → plan → implement cycle.

### Session 0 — Foundation & data model
**Depends on:** —
Clean project setup (XcodeGen, SwiftData + CloudKit container, entitlements). Core SwiftData
models: `Medication`, `Batch` (color-coded, time-based, daily/weekday recurrence), `BatchItem`
(join carrying per-batch quantity, e.g. 1 tablet AM / ½ tablet PM), `DoseLog` (per-medication,
with frozen snapshot fields), `MedicationChangeEvent` (the reasoning journal — added /
doseChanged / instructionsChanged / swapped / discontinued / reactivated / note), and a
`successor` self-link on `Medication` for swap continuity. App navigation skeleton (stubbed tabs).
Dev seed data (gated behind DEBUG). `HealthMetric` deferred to Session 6.
See [`2026-06-19-session-0-foundation-design.md`](2026-06-19-session-0-foundation-design.md).
**Dogfood state:** Launches; skeleton only — proves the schema.

### Session 1 — Medication & regime
**Depends on:** 0
Medication CRUD with **"why?" reasoning capture on add/edit** (writes a `MedicationChangeEvent`).
Color-coded, time-based batches; assign meds to batches with per-batch quantity. Color manager
(configure which pills are in each batch). The regime view. **Guided, atomic medication-change
workflow:** a structured flow for swaps that discontinues the old med, creates the replacement,
links them via `successor`, and *requires* a reasoning note — all written in one save, so the
caregiver can never leave the old med active or the replacement unlinked. The same note is
mandatory on dose/instruction changes.
**Dogfood state:** First real use — load the patient's actual meds/regime and use as a reference.

### Session 2 — Dose logging
**Depends on:** 1
Daily checklist interaction: mark each batch/med taken, not taken, and at what time. Writes
`DoseLog` entries.
**Dogfood state:** The daily-use loop — open it each day and log.

### Session 3 — Reminders & Live Activities
**Depends on:** 1, 2
Scheduled local notifications per batch time (UNUserNotifications). ActivityKit **Live Activity**
that actively "pesters" until the batch is logged (modeled after PillBuddy).
**Dogfood state:** Full intended daily experience with on-time prompting.

### Session 4 — Medication change journal & continuity
**Depends on:** 1, 2
Per-medication **reasoning timeline** (the *why* behind every change over time). Swap continuity
(e.g. beta blocker A → beta blocker B) by walking the `successor` chain, so reasoning and dose
history stay continuous across substitutions.
**Dogfood state:** Value compounds as meds change over weeks.

### Session 5 — Reporting
**Depends on:** 2, 4
Historic doses per drug, with a toggle between "when taken" and "when not taken" views.
**Open question:** the cut-off "Present" line in the README — likely report
presentation/printing/sharing; resolve during this session's brainstorm.
**Deferred from the daily-dose-allocation work (2026-06-20):** display **total medicine received**
(e.g. *"1.5 tablets · 45 mg"*) on dose-log / history surfaces. The numeric data needed is already
captured per dose (`DoseLog.snapshotStrengthValue` / `snapshotStrengthUnit`); only the presentation
remains — decide per-dose vs. per-day rollups and how PRN / partial / missed doses are summarized.
See [`2026-06-20-daily-dose-allocation-design.md`](2026-06-20-daily-dose-allocation-design.md).
**Dogfood state:** Useful once dose history has accumulated.

### Session 6 — Health metrics + HealthKit
**Depends on:** 0 (independent track — may be built ahead of Session 5)
Capture **Blood Pressure, Pulse / SpO₂, Weight, Water Intake** via a generic `HealthMetric`
model + metric-definition registry and two capture surfaces (scalar + vitals). One-way write to
Apple Health (HealthKit). **Sleep Quality dropped** (subjective, no clean Health mapping);
two-way sync out of scope. See
[`2026-06-19-session-6-health-metrics-design.md`](2026-06-19-session-6-health-metrics-design.md).
**Dogfood state:** Adds metric tracking that flows to Apple Health.

### Session 7 — Launch readiness: polish, TestFlight & public website *(later)*
**Depends on:** most
App polish and distribution prep **plus a public marketing website**, bundled because the
website's privacy policy is a hard prerequisite for HealthKit App Review and external TestFlight.

- **App polish:** onboarding, HealthKit/privacy usage strings, medical disclaimer copy, app icon.
- **TestFlight prep:** distribution signing/capabilities, App Privacy "nutrition label"
  questionnaire, App Store Connect metadata (incl. privacy-policy URL → the website below).
- **Public website** (`web/` in this repo), modeled on the `20four7` site in
  [`../televista/web`](../../../../televista/web): a **plain static site** (hand-written
  HTML/CSS, no build step), deployed to **Vercel** with a custom domain (CNAME) + Vercel Web
  Analytics. Three pages reusing one stylesheet:
  - **Landing** — caregiver-framed pitch (color-coded regimes, dose logging, reasoning journal,
    Health metrics). *Not* the ambient-TV framing of 20four7.
  - **Support** — contact / FAQ.
  - **Privacy policy** — satisfies the HealthKit/App Store privacy-policy requirement; states
    that data lives in the user's iCloud, is not shared/sold, and (per Session 6) that health
    metrics are written one-way to Apple Health and never read back into iCloud.
  - 20four7's `channels-catalog.json` remote-config piece is **not** carried over — PillDaddy
    has no remote catalog.

Each of polish / TestFlight / website may still be brainstormed and built as its own slice
within this session if it proves large.

## Next step

Kick off **Session 0** with its own brainstorm to nail down the data model and project setup.
