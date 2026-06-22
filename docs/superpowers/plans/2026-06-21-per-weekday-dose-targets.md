# Per-Weekday Dose Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a medication's prescribed dose vary by day of week (e.g. 1 on Thursday, 2 on Saturday) while keeping the allocation/accounting validation correct per day.

**Architecture:** Add an optional `weekdayDoseTargets: [Double]?` to `Medication` (`nil` = uniform, falls back to `dailyDoseTarget`). Make `DoseAllocation` day-aware: compute scheduled totals per weekday from each routine item × its routine's firing days, and reconcile each day against that day's target. A startup migration snapshots existing schedules so nothing is falsely flagged. UI gains progressive disclosure for variable targets and always communicates the target.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing. XcodeGen (`project.yml`) — sources are directory-globbed, so **any new file requires `xcodegen generate`** before it compiles.

**Spec:** [docs/superpowers/specs/2026-06-21-per-weekday-dose-targets-design.md](../specs/2026-06-21-per-weekday-dose-targets-design.md)

**Conventions used throughout:**
- Build: `xcodebuild build -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17'`
- Test (all): `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17'`
- Test (one suite): append `-only-testing:RoutineDosePlannerTests/<SuiteName>`
- Regenerate project after adding/removing files: `xcodegen generate`
- Weekday indexing is `Calendar`'s: 1 = Sunday … 7 = Saturday. Array index = `weekday - 1`.

---

## Task 1: Medication per-weekday target property and accessors

**Files:**
- Modify: `RoutineDosePlanner/Models/Medication.swift`
- Create: `RoutineDosePlanner/Services/WeekdayDoseTargets.swift`
- Test: `RoutineDosePlannerTests/WeekdayDoseTargetsTests.swift`

- [ ] **Step 1: Add the stored property and accessors to `Medication`**

In `RoutineDosePlanner/Models/Medication.swift`, add the property right after `dailyDoseTarget` (line 9):

```swift
    var dailyDoseTarget: Double = 1        // prescribed units per full dosing day (count)
    var weekdayDoseTargets: [Double]? = nil // nil = uniform (use dailyDoseTarget); else 7 values, index = weekday-1
```

Then add accessors after `strengthDescription` (after line 35):

```swift
    /// Prescribed target for a Calendar weekday (1=Sun … 7=Sat).
    func target(forWeekday wd: Int) -> Double {
        WeekdayDoseTargets.resolve(forWeekday: wd, daily: dailyDoseTarget, perWeekday: weekdayDoseTargets)
    }

    /// True when the prescription differs across days (drives UI disclosure).
    var hasVariableSchedule: Bool { weekdayDoseTargets != nil }
```

Note: SwiftData migrates this automatically (adding an optional property is a lightweight migration); no versioned schema needed. The init does not need the new property — it defaults to `nil`.

- [ ] **Step 2: Create the `WeekdayDoseTargets` helper**

Create `RoutineDosePlanner/Services/WeekdayDoseTargets.swift`:

```swift
import Foundation

/// Pure helpers for the per-weekday dose-target representation. Centralizes the
/// nil-means-uniform fallback and the collapse/expand used by editors so the rule
/// lives in exactly one place.
enum WeekdayDoseTargets {
    private static let tolerance = 0.0001

    /// Resolved target for a weekday (1=Sun…7=Sat): the per-weekday value when set,
    /// otherwise the uniform `daily` value.
    static func resolve(forWeekday wd: Int, daily: Double, perWeekday: [Double]?) -> Double {
        perWeekday?[wd - 1] ?? daily
    }

    /// A 7-value array for editing: the stored per-weekday values, or `daily`
    /// repeated when uniform.
    static func expand(daily: Double, perWeekday: [Double]?) -> [Double] {
        perWeekday ?? Array(repeating: daily, count: 7)
    }

    /// Collapse an edited 7-value array back to storage form: if every value is
    /// equal, return uniform (perWeekday = nil); otherwise keep the array. The
    /// returned `daily` is the first value (used as the uniform/fallback target).
    static func collapse(_ values: [Double]) -> (daily: Double, perWeekday: [Double]?) {
        precondition(values.count == 7, "weekday targets must have 7 values")
        let first = values[0]
        let uniform = values.allSatisfy { abs($0 - first) <= tolerance }
        return uniform ? (first, nil) : (first, values)
    }
}
```

- [ ] **Step 3: Write the failing tests**

Create `RoutineDosePlannerTests/WeekdayDoseTargetsTests.swift`:

```swift
import Testing
@testable import RoutineDosePlanner

struct WeekdayDoseTargetsTests {

    @Test func resolveFallsBackToDailyWhenNil() {
        #expect(WeekdayDoseTargets.resolve(forWeekday: 4, daily: 1.5, perWeekday: nil) == 1.5)
    }

    @Test func resolveUsesPerWeekdayValueWhenSet() {
        let perWeekday = [0, 0, 0, 0, 1, 0, 2.0] // Thu (5) = 1, Sat (7) = 2
        #expect(WeekdayDoseTargets.resolve(forWeekday: 5, daily: 0, perWeekday: perWeekday) == 1)
        #expect(WeekdayDoseTargets.resolve(forWeekday: 7, daily: 0, perWeekday: perWeekday) == 2)
    }

    @Test func expandRepeatsDailyWhenUniform() {
        #expect(WeekdayDoseTargets.expand(daily: 1.5, perWeekday: nil) == Array(repeating: 1.5, count: 7))
    }

    @Test func expandReturnsStoredArrayWhenVariable() {
        let perWeekday = [0, 0, 0, 0, 1, 0, 2.0]
        #expect(WeekdayDoseTargets.expand(daily: 0, perWeekday: perWeekday) == perWeekday)
    }

    @Test func collapseDetectsUniform() {
        let result = WeekdayDoseTargets.collapse(Array(repeating: 1.5, count: 7))
        #expect(result.daily == 1.5)
        #expect(result.perWeekday == nil)
    }

    @Test func collapseKeepsArrayWhenVariable() {
        let values = [0, 0, 0, 0, 1, 0, 2.0]
        let result = WeekdayDoseTargets.collapse(values)
        #expect(result.perWeekday == values)
    }
}
```

- [ ] **Step 4: Regenerate the project (two new files added)**

Run: `xcodegen generate`
Expected: "Created project at .../RoutineDosePlanner.xcodeproj"

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RoutineDosePlannerTests/WeekdayDoseTargetsTests`
Expected: PASS (6 tests)

- [ ] **Step 6: Commit**

```bash
git add RoutineDosePlanner/Models/Medication.swift RoutineDosePlanner/Services/WeekdayDoseTargets.swift RoutineDosePlannerTests/WeekdayDoseTargetsTests.swift RoutineDosePlanner.xcodeproj
git commit -m "Add per-weekday dose target to Medication"
```

---

## Task 2: Shared `firingWeekdays` on Routine

**Files:**
- Modify: `RoutineDosePlanner/Models/Routine.swift`
- Modify: `RoutineDosePlanner/Services/DayQuery.swift:54-61`
- Test: `RoutineDosePlannerTests/RoutineFiringWeekdaysTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RoutineDosePlannerTests/RoutineFiringWeekdaysTests.swift`:

```swift
import Testing
@testable import RoutineDosePlanner

struct RoutineFiringWeekdaysTests {

    @Test func dailyRoutineFiresEveryWeekday() {
        let routine = Routine(name: "Daily", recurrenceKind: .daily)
        #expect(routine.firingWeekdays == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func weekdayRoutineFiresOnlyItsDaysSorted() {
        let routine = Routine(name: "Thu/Sat", recurrenceKind: .weekdays, weekdays: [7, 5])
        #expect(routine.firingWeekdays == [5, 7])
    }

    @Test func weekdayRoutineWithNoDaysFiresNothing() {
        let routine = Routine(name: "Empty", recurrenceKind: .weekdays, weekdays: nil)
        #expect(routine.firingWeekdays == [])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodegen generate` (new test file), then
`xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RoutineDosePlannerTests/RoutineFiringWeekdaysTests`
Expected: FAIL — `value of type 'Routine' has no member 'firingWeekdays'`

- [ ] **Step 3: Add the computed property to `Routine`**

In `RoutineDosePlanner/Models/Routine.swift`, add before the `init` (after line 15):

```swift
    /// Calendar weekdays (1=Sun…7=Sat) this routine fires on. Daily ⇒ all 7;
    /// weekdays ⇒ its configured list, sorted. Single source of recurrence truth.
    var firingWeekdays: [Int] {
        switch RecurrenceKind(rawValue: recurrenceKind) ?? .daily {
        case .daily: return [1, 2, 3, 4, 5, 6, 7]
        case .weekdays: return (weekdays ?? []).sorted()
        }
    }
```

- [ ] **Step 4: Refactor `DayQuery.recurs` to use it**

In `RoutineDosePlanner/Services/DayQuery.swift`, replace the body of `recurs` (lines 54-61):

```swift
    static func recurs(_ routine: Routine, on day: Date) -> Bool {
        let wd = Calendar.current.component(.weekday, from: day)
        return routine.firingWeekdays.contains(wd)
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RoutineDosePlannerTests/RoutineFiringWeekdaysTests -only-testing:RoutineDosePlannerTests/DayQueryTests`
Expected: PASS (new suite + existing DayQuery suite still green)

- [ ] **Step 6: Commit**

```bash
git add RoutineDosePlanner/Models/Routine.swift RoutineDosePlanner/Services/DayQuery.swift RoutineDosePlannerTests/RoutineFiringWeekdaysTests.swift RoutineDosePlanner.xcodeproj
git commit -m "Add Routine.firingWeekdays and route DayQuery.recurs through it"
```

---

## Task 3: Day-aware DoseAllocation (the core fix)

This is the keystone. We add `scheduledByWeekday` / `remaining(_:addingTo:)`, rewrite `status` to reconcile per day, and update `DoseAllocationTests` to the day-aware semantics (including the motivating Thu/Sat case). The scalar `allocated(_:)` / `remaining(_:)` / strength helpers stay for now (other call sites still use them) and are removed in Task 8.

**Files:**
- Modify: `RoutineDosePlanner/Services/DoseAllocation.swift`
- Test: `RoutineDosePlannerTests/DoseAllocationTests.swift`

- [ ] **Step 1: Write the failing tests**

Replace the entire body of `RoutineDosePlannerTests/DoseAllocationTests.swift` with:

```swift
import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct DoseAllocationTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    /// A scheduled med built from (recurrence, quantity) routine placements.
    private func med(daily: Double, perWeekday: [Double]? = nil,
                     placements: [(RecurrenceKind, [Int]?, Double)]) -> Medication {
        let m = Medication(name: "Test", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: daily)
        m.weekdayDoseTargets = perWeekday
        context.insert(m)
        for (kind, days, qty) in placements {
            let r = Routine(name: "R", recurrenceKind: kind, weekdays: days)
            context.insert(r)
            context.insert(RoutineItem(quantity: qty, medication: m, routine: r))
        }
        return m
    }

    @Test func scheduledByWeekdayDailyRoutineHitsEveryDay() {
        let m = med(daily: 1, placements: [(.daily, nil, 1.0)])
        #expect(DoseAllocation.scheduledByWeekday(m) == Array(repeating: 1.0, count: 7))
    }

    @Test func scheduledByWeekdayWeekdayRoutineHitsOnlyItsDays() {
        // Thu (5) = 1, Sat (7) = 2
        let m = med(daily: 0, placements: [(.weekdays, [5], 1.0), (.weekdays, [7], 2.0)])
        let s = DoseAllocation.scheduledByWeekday(m)
        #expect(s[4] == 1.0) // Thursday
        #expect(s[6] == 2.0) // Saturday
        #expect(s[0] == 0.0) // Sunday
    }

    @Test func scheduledByWeekdayOverlappingRoutinesSumOnSameDay() {
        // morning daily 1 + evening daily 0.5 => 1.5 every day
        let m = med(daily: 1.5, placements: [(.daily, nil, 1.0), (.daily, nil, 0.5)])
        #expect(DoseAllocation.scheduledByWeekday(m) == Array(repeating: 1.5, count: 7))
    }

    @Test func variableScheduleMatchingTargetsIsFull() {
        // THE MOTIVATING CASE: 1 Thursday, 2 Saturday, targets Thu=1/Sat=2/else=0.
        var perWeekday = Array(repeating: 0.0, count: 7)
        perWeekday[4] = 1; perWeekday[6] = 2
        let m = med(daily: 0, perWeekday: perWeekday,
                    placements: [(.weekdays, [5], 1.0), (.weekdays, [7], 2.0)])
        #expect(DoseAllocation.status(m) == .full)
    }

    @Test func statusOverWhenAnyDayExceeds() {
        // daily target 1, but a Saturday extra pushes Saturday to 2.
        let m = med(daily: 1, placements: [(.daily, nil, 1.0), (.weekdays, [7], 1.0)])
        #expect(DoseAllocation.status(m) == .over)
    }

    @Test func statusUnderWhenADayIsBelowAndNoneOver() {
        let m = med(daily: 2, placements: [(.daily, nil, 0.5)])
        #expect(DoseAllocation.status(m) == .under)
    }

    @Test func statusFullWhenUniformMatches() {
        let m = med(daily: 1.5, placements: [(.daily, nil, 1.0), (.daily, nil, 0.5)])
        #expect(DoseAllocation.status(m) == .full)
    }

    @Test func remainingAddingToIsMinSlackAcrossRoutineDays() {
        // daily target 2, already 0.5/day scheduled => 1.5 slack on every day.
        let m = med(daily: 2, placements: [(.daily, nil, 0.5)])
        let satRoutine = Routine(name: "Sat", recurrenceKind: .weekdays, weekdays: [7])
        context.insert(satRoutine)
        #expect(DoseAllocation.remaining(m, addingTo: satRoutine) == 1.5)
    }

    @Test func remainingAddingToDailyRoutineConstrainedByTightestDay() {
        // Saturday already full (target 1, scheduled 1); other days have slack.
        var perWeekday = Array(repeating: 2.0, count: 7)
        perWeekday[6] = 1 // Saturday target 1
        let m = med(daily: 2, perWeekday: perWeekday,
                    placements: [(.weekdays, [7], 1.0)])
        let daily = Routine(name: "Daily", recurrenceKind: .daily)
        context.insert(daily)
        // Adding to a daily routine is constrained by Saturday's 0 slack.
        #expect(DoseAllocation.remaining(m, addingTo: daily) == 0)
    }

    @Test func needsAttentionTrueWhenUnderAndScheduled() {
        #expect(DoseAllocation.needsAttention(med(daily: 2, placements: [(.daily, nil, 0.5)])))
    }

    @Test func needsAttentionFalseWhenFull() {
        #expect(!DoseAllocation.needsAttention(med(daily: 1, placements: [(.daily, nil, 1.0)])))
    }

    @Test func needsAttentionFalseForPRN() {
        let m = Medication(name: "PRN", strengthValue: 500, strengthUnit: "mg", dailyDoseTarget: 1, isPRN: true)
        context.insert(m)
        #expect(!DoseAllocation.needsAttention(m))
    }

    @Test func needsAttentionFalseForDiscontinued() {
        let m = med(daily: 2, placements: [(.daily, nil, 0.5)])
        m.isActive = false
        #expect(!DoseAllocation.needsAttention(m))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RoutineDosePlannerTests/DoseAllocationTests`
Expected: FAIL — `scheduledByWeekday` / `remaining(_:addingTo:)` not found; `variableScheduleMatchingTargetsIsFull` fails under old summed `status`.

- [ ] **Step 3: Add the day-aware methods and rewrite `status`**

In `RoutineDosePlanner/Services/DoseAllocation.swift`, add these methods inside the `enum DoseAllocation` (keep the existing `allocated`, `remaining(_:)`, strength helpers for now). Replace the existing `status(_:)` (lines 26-31) with the per-day version:

```swift
    /// Total units scheduled on each Calendar weekday (1=Sun…7=Sat). Index = weekday-1.
    static func scheduledByWeekday(_ med: Medication) -> [Double] {
        var totals = [Double](repeating: 0, count: 7)
        for item in med.routineItems ?? [] {
            guard let routine = item.routine else { continue }
            for wd in routine.firingWeekdays { totals[wd - 1] += item.quantity }
        }
        return totals
    }

    static func status(_ med: Medication) -> Status {
        let scheduled = scheduledByWeekday(med)
        var anyUnder = false
        for wd in 1...7 {
            let target = med.target(forWeekday: wd)
            if isOverTarget(allocated: scheduled[wd - 1], target: target) { return .over }
            if scheduled[wd - 1] < target - tolerance { anyUnder = true }
        }
        return anyUnder ? .under : .full
    }

    /// Max additional quantity addable to `routine` without pushing any of its
    /// firing days over target — the minimum slack across those days.
    static func remaining(_ med: Medication, addingTo routine: Routine) -> Double {
        let scheduled = scheduledByWeekday(med)
        return routine.firingWeekdays
            .map { max(0, med.target(forWeekday: $0) - scheduled[$0 - 1]) }
            .min() ?? 0
    }

    /// True if adding `quantity` to `routine` would push any firing day over target.
    static func adding(_ quantity: Double, to routine: Routine, exceedsTargetFor med: Medication) -> Bool {
        quantity > remaining(med, addingTo: routine) + tolerance
    }

    /// True if any weekday's total across `placements` exceeds the resolved target
    /// for that day. Used to validate prospective add/change before persisting.
    static func placementsOverTarget(
        daily: Double, perWeekday: [Double]?,
        placements: [(routine: Routine, quantity: Double)]
    ) -> Bool {
        var totals = [Double](repeating: 0, count: 7)
        for p in placements {
            for wd in p.routine.firingWeekdays { totals[wd - 1] += p.quantity }
        }
        for wd in 1...7 {
            let target = WeekdayDoseTargets.resolve(forWeekday: wd, daily: daily, perWeekday: perWeekday)
            if isOverTarget(allocated: totals[wd - 1], target: target) { return true }
        }
        return false
    }

    /// True if moving `item` to `routine` would push any of the destination's days
    /// over target. Relocation changes which days the quantity lands on.
    static func moving(_ item: RoutineItem, to routine: Routine) -> Bool {
        guard let med = item.medication, let from = item.routine else { return false }
        var totals = scheduledByWeekday(med)
        for wd in from.firingWeekdays { totals[wd - 1] -= item.quantity }
        for wd in routine.firingWeekdays { totals[wd - 1] += item.quantity }
        for wd in 1...7 where isOverTarget(allocated: totals[wd - 1], target: med.target(forWeekday: wd)) {
            return true
        }
        return false
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RoutineDosePlannerTests/DoseAllocationTests`
Expected: PASS — including `variableScheduleMatchingTargetsIsFull` (the bug is fixed).

- [ ] **Step 5: Build the whole app to confirm nothing else broke**

Run: `xcodebuild build -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED (scalar `allocated`/`remaining` still present for existing callers).

- [ ] **Step 6: Commit**

```bash
git add RoutineDosePlanner/Services/DoseAllocation.swift RoutineDosePlannerTests/DoseAllocationTests.swift
git commit -m "Make DoseAllocation day-aware (per-weekday status and capacity)"
```

---

## Task 4: Startup snapshot migration

**Files:**
- Create: `RoutineDosePlanner/Services/WeekdayTargetMigration.swift`
- Modify: `RoutineDosePlanner/RoutineDosePlannerApp.swift:53`
- Test: `RoutineDosePlannerTests/WeekdayTargetMigrationTests.swift`

- [ ] **Step 1: Create the migration**

Create `RoutineDosePlanner/Services/WeekdayTargetMigration.swift`:

```swift
import Foundation
import SwiftData

/// One-time backfill of per-weekday targets. For meds whose existing schedule is
/// NOT uniform across the week, snapshot the currently-scheduled per-weekday totals
/// into `weekdayDoseTargets` so they keep reporting `.full` under the new day-aware
/// accounting. Uniform daily meds are left as `nil`. Idempotent.
@MainActor
enum WeekdayTargetMigration {
    private static let tolerance = 0.0001

    static func backfill(in context: ModelContext) {
        let userDefaultsKey = "didRunWeekdayTargetBackfill"
        guard !UserDefaults.standard.bool(forKey: userDefaultsKey) else { return }

        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        var changed = false
        for med in meds where !med.isPRN && med.weekdayDoseTargets == nil {
            let scheduled = DoseAllocation.scheduledByWeekday(med)
            if scheduled.contains(where: { abs($0 - med.dailyDoseTarget) > tolerance }) {
                med.weekdayDoseTargets = scheduled
                changed = true
            }
        }
        if changed { try? context.save() }

        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }
}
```

- [ ] **Step 2: Wire it into app startup**

In `RoutineDosePlanner/RoutineDosePlannerApp.swift`, after the existing backfill call (line 53):

```swift
        DoseLogMigration.backfillPRNFlag(in: container.mainContext)
        WeekdayTargetMigration.backfill(in: container.mainContext)
```

- [ ] **Step 3: Write the failing tests**

Create `RoutineDosePlannerTests/WeekdayTargetMigrationTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import RoutineDosePlanner

// Serialized: mutates the process-global migration UserDefaults flag.
@Suite(.serialized)
@MainActor
struct WeekdayTargetMigrationTests {

    private func freshContext() throws -> ModelContext {
        try ModelTestSupport.makeContainer().mainContext
    }

    @Test func partialWeekMedSnapshotsAndStaysFull() throws {
        let key = "didRunWeekdayTargetBackfill"
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let context = try freshContext()
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.5)
        context.insert(med)
        // Scheduled only Mon–Fri (weekdays 2–6) at 1.5.
        let routine = Routine(name: "Weekdays", recurrenceKind: .weekdays, weekdays: [2, 3, 4, 5, 6])
        context.insert(routine)
        context.insert(RoutineItem(quantity: 1.5, medication: med, routine: routine))
        try context.save()

        WeekdayTargetMigration.backfill(in: context)

        #expect(med.weekdayDoseTargets != nil)
        #expect(med.weekdayDoseTargets?[0] == 0)   // Sunday
        #expect(med.weekdayDoseTargets?[1] == 1.5) // Monday
        #expect(DoseAllocation.status(med) == .full)
    }

    @Test func uniformDailyMedStaysNil() throws {
        let key = "didRunWeekdayTargetBackfill"
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let context = try freshContext()
        let med = Medication(name: "Vitamin D", strengthValue: 1000, strengthUnit: "IU", dailyDoseTarget: 1)
        context.insert(med)
        let routine = Routine(name: "Daily", recurrenceKind: .daily)
        context.insert(routine)
        context.insert(RoutineItem(quantity: 1.0, medication: med, routine: routine))
        try context.save()

        WeekdayTargetMigration.backfill(in: context)

        #expect(med.weekdayDoseTargets == nil)
        #expect(DoseAllocation.status(med) == .full)
    }

    @Test func isIdempotent() throws {
        let key = "didRunWeekdayTargetBackfill"
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let context = try freshContext()
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.5)
        context.insert(med)
        let routine = Routine(name: "Weekdays", recurrenceKind: .weekdays, weekdays: [2, 3, 4, 5, 6])
        context.insert(routine)
        context.insert(RoutineItem(quantity: 1.5, medication: med, routine: routine))
        try context.save()

        WeekdayTargetMigration.backfill(in: context)
        // A second run must change nothing (flag already set).
        med.weekdayDoseTargets = nil
        WeekdayTargetMigration.backfill(in: context)
        #expect(med.weekdayDoseTargets == nil)
    }
}
```

- [ ] **Step 4: Regenerate the project (new files)**

Run: `xcodegen generate`

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RoutineDosePlannerTests/WeekdayTargetMigrationTests`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add RoutineDosePlanner/Services/WeekdayTargetMigration.swift RoutineDosePlanner/RoutineDosePlannerApp.swift RoutineDosePlannerTests/WeekdayTargetMigrationTests.swift RoutineDosePlanner.xcodeproj
git commit -m "Add startup migration snapshotting per-weekday targets"
```

---

## Task 5: Day-aware validation in MedicationService

`addMedication` and `changeDose` gain an optional `weekdayDoseTargets` parameter and validate per day; `addToRoutine` and `moveToRoutine` use the routine-aware checks.

**Files:**
- Modify: `RoutineDosePlanner/Services/MedicationService.swift`
- Test: `RoutineDosePlannerTests/MedicationServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Append these tests inside `struct MedicationServiceTests` in `RoutineDosePlannerTests/MedicationServiceTests.swift` (before the final closing brace):

```swift
    @Test
    func testAddToRoutineAllowsSameQuantityOnNonOverlappingDays() throws {
        // Thu target 1, Sat target 2. Adding 2 to a Saturday routine is fine even
        // though a Thursday routine already holds 1 (different days don't stack).
        let thu = Routine(name: "Thu", recurrenceKind: .weekdays, weekdays: [5])
        let sat = Routine(name: "Sat", recurrenceKind: .weekdays, weekdays: [7])
        context.insert(thu); context.insert(sat)
        var perWeekday = Array(repeating: 0.0, count: 7)
        perWeekday[4] = 1; perWeekday[6] = 2
        let med = try MedicationService.addMedication(
            name: "Warfarin", strengthValue: 5, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 0, weekdayDoseTargets: perWeekday,
            placements: [(routine: thu, quantity: 1.0)], reason: "", in: context)

        try MedicationService.addToRoutine(med, sat, quantity: 2.0, in: context)

        #expect(DoseAllocation.status(med) == .full)
    }

    @Test
    func testAddToRoutineRejectsOverfillingASingleDay() throws {
        // Daily target 1, already a daily routine at 1 => any added daily routine overflows.
        let morning = Routine(name: "Morning", recurrenceKind: .daily)
        let evening = Routine(name: "Evening", recurrenceKind: .daily)
        context.insert(morning); context.insert(evening)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [(routine: morning, quantity: 1.0)], reason: "", in: context)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addToRoutine(med, evening, quantity: 0.5, in: context)
        }
    }

    @Test
    func testAddMedicationRejectsVariableTargetOverflowOnOneDay() throws {
        let sat = Routine(name: "Sat", recurrenceKind: .weekdays, weekdays: [7])
        context.insert(sat)
        var perWeekday = Array(repeating: 0.0, count: 7)
        perWeekday[6] = 1 // Saturday target 1
        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addMedication(
                name: "Warfarin", strengthValue: 5, strengthUnit: "mg", form: "tablet",
                isPRN: false, notes: "", dailyDoseTarget: 0, weekdayDoseTargets: perWeekday,
                placements: [(routine: sat, quantity: 2.0)], reason: "", in: context)
        }
    }

    @Test
    func testChangeDoseStoresVariableTargets() throws {
        let thu = Routine(name: "Thu", recurrenceKind: .weekdays, weekdays: [5])
        let sat = Routine(name: "Sat", recurrenceKind: .weekdays, weekdays: [7])
        context.insert(thu); context.insert(sat)
        let med = try MedicationService.addMedication(
            name: "Warfarin", strengthValue: 5, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [(routine: thu, quantity: 1.0)], reason: "", in: context)

        var perWeekday = Array(repeating: 0.0, count: 7)
        perWeekday[4] = 1; perWeekday[6] = 2
        try MedicationService.changeDose(
            med, newStrengthValue: 5, newStrengthUnit: "mg", newDailyDoseTarget: 0,
            newWeekdayDoseTargets: perWeekday,
            placements: [(routine: thu, quantity: 1.0), (routine: sat, quantity: 2.0)],
            reason: "Adjusted weekly schedule", in: context)

        #expect(med.weekdayDoseTargets == perWeekday)
        #expect(DoseAllocation.status(med) == .full)
    }

    @Test
    func testMoveToRoutineRejectedWhenDestinationDayWouldOverfill() throws {
        // Saturday target 1 already met by a Saturday item; moving a Thursday item
        // (qty 1) onto Saturday would make Saturday 2 > 1.
        let thu = Routine(name: "Thu", recurrenceKind: .weekdays, weekdays: [5])
        let sat = Routine(name: "Sat", recurrenceKind: .weekdays, weekdays: [7])
        context.insert(thu); context.insert(sat)
        var perWeekday = Array(repeating: 0.0, count: 7)
        perWeekday[4] = 1; perWeekday[6] = 1
        let med = try MedicationService.addMedication(
            name: "Warfarin", strengthValue: 5, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 0, weekdayDoseTargets: perWeekday,
            placements: [(routine: thu, quantity: 1.0), (routine: sat, quantity: 1.0)],
            reason: "", in: context)
        let thuItem = try #require((med.routineItems ?? []).first { $0.routine?.name == "Thu" })

        #expect(throws: MembershipError.alreadyInRoutine) {
            // Sat already has this med — move is blocked by the duplicate guard first.
            try MedicationService.moveToRoutine(thuItem, to: sat, in: context)
        }
    }

    @Test
    func testMoveToRoutineRejectedOnOverfillToEmptyDestination() throws {
        // Med on Thursday (target Thu=1, Sat=0). Moving it to Saturday (target 0)
        // would make Saturday 1 > 0.
        let thu = Routine(name: "Thu", recurrenceKind: .weekdays, weekdays: [5])
        let sat = Routine(name: "Sat", recurrenceKind: .weekdays, weekdays: [7])
        context.insert(thu); context.insert(sat)
        var perWeekday = Array(repeating: 0.0, count: 7)
        perWeekday[4] = 1 // Thu target 1, Sat target 0
        let med = try MedicationService.addMedication(
            name: "Warfarin", strengthValue: 5, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 0, weekdayDoseTargets: perWeekday,
            placements: [(routine: thu, quantity: 1.0)], reason: "", in: context)
        let thuItem = try #require(med.routineItems?.first)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.moveToRoutine(thuItem, to: sat, in: context)
        }
        #expect(thuItem.routine?.name == "Thu") // unchanged
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RoutineDosePlannerTests/MedicationServiceTests`
Expected: FAIL — `addMedication`/`changeDose` have no `weekdayDoseTargets` parameter; move/add checks not day-aware.

- [ ] **Step 3: Update `addMedication`**

In `RoutineDosePlanner/Services/MedicationService.swift`, change the signature and validation of `addMedication` (lines 27-44). Add the parameter after `dailyDoseTarget`:

```swift
    @discardableResult
    static func addMedication(
        name: String, strengthValue: Double, strengthUnit: String, form: String,
        isPRN: Bool, notes: String, dailyDoseTarget: Double = 1,
        weekdayDoseTargets: [Double]? = nil,
        placements: [(routine: Routine, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws -> Medication {
        if !isPRN {
            if DoseAllocation.placementsOverTarget(
                daily: dailyDoseTarget, perWeekday: weekdayDoseTargets, placements: placements) {
                throw DoseAllocationError.exceedsDailyTarget
            }
        }
        let med = Medication(name: name, strengthValue: strengthValue, strengthUnit: strengthUnit,
                             dailyDoseTarget: dailyDoseTarget, form: form,
                             generalNotes: notes, isPRN: isPRN)
        med.weekdayDoseTargets = weekdayDoseTargets
        context.insert(med)
```

(Leave the rest of `addMedication` — the placement loop, change event, save — unchanged.)

- [ ] **Step 4: Update `changeDose`**

Change the signature and validation of `changeDose` (lines 62-80). Add the parameter and swap the check:

```swift
    static func changeDose(
        _ med: Medication,
        newStrengthValue: Double, newStrengthUnit: String,
        newDailyDoseTarget: Double,
        newWeekdayDoseTargets: [Double]? = nil,
        placements: [(routine: Routine, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws {
        try requireReason(reason)

        if DoseAllocation.placementsOverTarget(
            daily: newDailyDoseTarget, perWeekday: newWeekdayDoseTargets, placements: placements) {
            throw DoseAllocationError.exceedsDailyTarget
        }

        let oldSummary = doseSummary(med)
        med.strengthValue = newStrengthValue
        med.strengthUnit = newStrengthUnit
        med.dailyDoseTarget = newDailyDoseTarget
        med.weekdayDoseTargets = newWeekdayDoseTargets
```

(Leave the membership reconciliation, event, and save below unchanged.)

- [ ] **Step 5: Update `addToRoutine` and `moveToRoutine`**

Replace the cap check in `addToRoutine` (line 118):

```swift
        if DoseAllocation.adding(quantity, to: routine, exceedsTargetFor: med) {
            throw DoseAllocationError.exceedsDailyTarget
        }
```

In `moveToRoutine`, after the duplicate guard and before mutating (after line 148), add the day-aware check:

```swift
        if DoseAllocation.moving(item, to: routine) {
            throw DoseAllocationError.exceedsDailyTarget
        }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RoutineDosePlannerTests/MedicationServiceTests`
Expected: PASS (existing + new tests). Existing daily-routine tests still pass because daily routines fire all 7 days, so per-day totals equal the old summed totals.

- [ ] **Step 7: Build the app (call sites use defaulted new params)**

Run: `xcodebuild build -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED — `ChangeDoseSheet`/`MedicationEditor` still compile (new params default to `nil`).

- [ ] **Step 8: Commit**

```bash
git add RoutineDosePlanner/Services/MedicationService.swift RoutineDosePlannerTests/MedicationServiceTests.swift
git commit -m "Validate dose allocation per weekday in MedicationService"
```

---

## Task 6: Pure formatters — dose summary and recurrence label

These produce the strings the views will show, so they are unit-tested here and consumed by views in Task 7.

**Files:**
- Create: `RoutineDosePlanner/Helpers/DoseSummaryFormatter.swift`
- Create: `RoutineDosePlanner/Helpers/RecurrenceLabel.swift`
- Test: `RoutineDosePlannerTests/DoseSummaryFormatterTests.swift`

- [ ] **Step 1: Create `DoseSummaryFormatter`**

Create `RoutineDosePlanner/Helpers/DoseSummaryFormatter.swift`:

```swift
import Foundation

/// Builds human-readable dose strings for the medication detail view. Pure and
/// unit-testable; weekday names come from a fixed short-symbol list (1=Sun…7=Sat).
enum DoseSummaryFormatter {
    static let shortWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// The prescribed target. Uniform → "1.5 tablet/day · 45 mg/day".
    /// Variable → "Thu 1 · Sat 2 · 3 tablet/wk".
    static func summary(for med: Medication) -> String {
        let form = med.form
        if let perWeekday = med.weekdayDoseTargets {
            let parts = (1...7).compactMap { wd -> String? in
                let qty = perWeekday[wd - 1]
                guard qty > 0 else { return nil }
                return "\(shortWeekdays[wd - 1]) \(DoseFormat.qty(qty))"
            }
            let weekly = perWeekday.reduce(0, +)
            return (parts + ["\(DoseFormat.qty(weekly)) \(form)/wk"]).joined(separator: " · ")
        } else {
            let perDayStrength = med.dailyDoseTarget * med.strengthValue
            return "\(DoseFormat.qty(med.dailyDoseTarget)) \(form)/day · \(DoseFormat.qty(perDayStrength)) \(med.strengthUnit)/day"
        }
    }

    /// Description of the under/over mismatch, or nil when full. Names the worst
    /// offending day for variable schedules.
    static func mismatch(for med: Medication) -> String? {
        guard DoseAllocation.status(med) != .full else { return nil }
        let scheduled = DoseAllocation.scheduledByWeekday(med)
        // Prefer an over day; else the first under day.
        for wd in 1...7 where scheduled[wd - 1] > med.target(forWeekday: wd) + 0.0001 {
            return dayMismatch(wd, scheduled: scheduled[wd - 1], target: med.target(forWeekday: wd), form: med.form)
        }
        for wd in 1...7 where scheduled[wd - 1] < med.target(forWeekday: wd) - 0.0001 {
            return dayMismatch(wd, scheduled: scheduled[wd - 1], target: med.target(forWeekday: wd), form: med.form)
        }
        return nil
    }

    private static func dayMismatch(_ wd: Int, scheduled: Double, target: Double, form: String) -> String {
        "\(shortWeekdays[wd - 1]): \(DoseFormat.qty(scheduled)) of \(DoseFormat.qty(target)) \(form)"
    }
}
```

- [ ] **Step 2: Create `RecurrenceLabel`**

Create `RoutineDosePlanner/Helpers/RecurrenceLabel.swift`:

```swift
import Foundation

/// Short label for a routine's recurrence, for inline display next to a routine
/// name. Returns nil for daily routines (no label needed). Variable days are
/// listed comma-separated, e.g. "Thu, Sat".
enum RecurrenceLabel {
    static func short(for routine: Routine) -> String? {
        switch RecurrenceKind(rawValue: routine.recurrenceKind) ?? .daily {
        case .daily:
            return nil
        case .weekdays:
            let days = routine.firingWeekdays
            guard !days.isEmpty else { return nil }
            return days.map { DoseSummaryFormatter.shortWeekdays[$0 - 1] }.joined(separator: ", ")
        }
    }
}
```

- [ ] **Step 3: Write the failing tests**

Create `RoutineDosePlannerTests/DoseSummaryFormatterTests.swift`:

```swift
import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct DoseSummaryFormatterTests {

    private let context: ModelContext
    init() throws { self.context = try ModelTestSupport.makeContainer().mainContext }

    @Test func uniformSummaryShowsPerDayCountAndStrength() {
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.5, form: "tablet")
        context.insert(med)
        #expect(DoseSummaryFormatter.summary(for: med) == "1.5 tablet/day · 45 mg/day")
    }

    @Test func variableSummaryListsDosingDaysAndWeeklyTotal() {
        let med = Medication(name: "Warfarin", strengthValue: 5, strengthUnit: "mg",
                             dailyDoseTarget: 0, form: "tablet")
        var perWeekday = Array(repeating: 0.0, count: 7)
        perWeekday[4] = 1; perWeekday[6] = 2 // Thu 1, Sat 2
        med.weekdayDoseTargets = perWeekday
        context.insert(med)
        #expect(DoseSummaryFormatter.summary(for: med) == "Thu 1 · Sat 2 · 3 tablet/wk")
    }

    @Test func mismatchNilWhenFull() {
        let med = Medication(name: "Daily", strengthValue: 10, strengthUnit: "mg",
                             dailyDoseTarget: 1, form: "tablet")
        context.insert(med)
        let routine = Routine(name: "Daily", recurrenceKind: .daily)
        context.insert(routine)
        context.insert(RoutineItem(quantity: 1.0, medication: med, routine: routine))
        #expect(DoseSummaryFormatter.mismatch(for: med) == nil)
    }

    @Test func mismatchNamesOverDay() {
        let med = Medication(name: "Daily", strengthValue: 10, strengthUnit: "mg",
                             dailyDoseTarget: 1, form: "tablet")
        context.insert(med)
        context.insert(RoutineItem(quantity: 1.0, medication: med,
                                   routine: insertRoutine(.daily, nil)))
        context.insert(RoutineItem(quantity: 1.0, medication: med,
                                   routine: insertRoutine(.weekdays, [7]))) // extra Saturday
        #expect(DoseSummaryFormatter.mismatch(for: med) == "Sat: 2 of 1 tablet")
    }

    @Test func recurrenceLabelNilForDaily() {
        #expect(RecurrenceLabel.short(for: Routine(name: "D", recurrenceKind: .daily)) == nil)
    }

    @Test func recurrenceLabelListsWeekdays() {
        let r = Routine(name: "W", recurrenceKind: .weekdays, weekdays: [7, 5])
        #expect(RecurrenceLabel.short(for: r) == "Thu, Sat")
    }

    private func insertRoutine(_ kind: RecurrenceKind, _ days: [Int]?) -> Routine {
        let r = Routine(name: "R", recurrenceKind: kind, weekdays: days)
        context.insert(r)
        return r
    }
}
```

- [ ] **Step 4: Regenerate and run the tests**

Run: `xcodegen generate`, then
`xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RoutineDosePlannerTests/DoseSummaryFormatterTests`
Expected: PASS (7 tests). If `DoseFormat.qty(1.5)` formatting differs (e.g. "1.5"), adjust expected strings to match `DoseFormat.qty` output — verify by reading `RoutineDosePlanner/Helpers/DoseFormat.swift` first.

- [ ] **Step 5: Commit**

```bash
git add RoutineDosePlanner/Helpers/DoseSummaryFormatter.swift RoutineDosePlanner/Helpers/RecurrenceLabel.swift RoutineDosePlannerTests/DoseSummaryFormatterTests.swift RoutineDosePlanner.xcodeproj
git commit -m "Add dose-summary and recurrence-label formatters"
```

---

## Task 7: UI wiring — summary row, day labels, capacity captions, progressive disclosure

SwiftUI views aren't unit-tested in this project, so these steps verify via build + manual check. The logic they call is already covered by Tasks 1–6.

**Files:**
- Modify: `RoutineDosePlanner/Views/Meds/DoseAllocationBadge.swift` → becomes `DoseSummaryRow`
- Modify: `RoutineDosePlanner/Views/Meds/MedicationDetailView.swift`
- Modify: `RoutineDosePlanner/Views/Meds/ChangeDoseSheet.swift`
- Modify: `RoutineDosePlanner/Views/Meds/MedicationEditor.swift`
- Modify: `RoutineDosePlanner/Views/Meds/RoutineMembershipSheets.swift` (AddToRoutineSheet caption + cap)
- Modify: `RoutineDosePlanner/Views/Meds/RoutineEditor.swift:111,131` (routine-aware remaining)

- [ ] **Step 1: Turn `DoseAllocationBadge` into `DoseSummaryRow`**

Replace the contents of `RoutineDosePlanner/Views/Meds/DoseAllocationBadge.swift`:

```swift
import SwiftUI

/// Always shows the prescribed dose target for a scheduled med; appends an amber
/// caution line when the scheduled allocation does not match the target. Renders
/// nothing for PRN meds.
struct DoseSummaryRow: View {
    let medication: Medication

    var body: some View {
        if !medication.isPRN {
            VStack(alignment: .leading, spacing: 2) {
                Text(DoseSummaryFormatter.summary(for: medication))
                    .font(.callout)
                if let mismatch = DoseSummaryFormatter.mismatch(for: medication) {
                    Label(mismatch, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Use `DoseSummaryRow` in the detail view and label schedule days**

In `RoutineDosePlanner/Views/Meds/MedicationDetailView.swift`, replace line 24:

```swift
                DoseSummaryRow(medication: medication)
```

Then in the Schedule section, replace the routine row's label `Text(item.routine?.name ?? "—")` (line 52) with a name + day-label stack:

```swift
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.routine?.name ?? "—")
                                    if let routine = item.routine, let days = RecurrenceLabel.short(for: routine) {
                                        Text(days).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
```

And update the "Add to routine" disabled check (line 61) to enable when any routine still has slack:

```swift
                    Button("Add to routine…") { sheet = .addToRoutine }
                        .disabled(!hasAnyRoutineSlack)
```

Add this computed property to `MedicationDetailView` (after the `enum DetailSheet` block):

```swift
    @Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
    private var allRoutines: [Routine]

    private var hasAnyRoutineSlack: Bool {
        let present = Set((medication.routineItems ?? []).compactMap { $0.routine?.persistentModelID })
        return allRoutines
            .filter { !present.contains($0.persistentModelID) }
            .contains { DoseAllocation.remaining(medication, addingTo: $0) > 0 }
    }
```

- [ ] **Step 3: Routine-aware capacity in `AddToRoutineSheet`**

In `RoutineDosePlanner/Views/Meds/RoutineMembershipSheets.swift`, the capacity now depends on the selected routine. Replace the `DoseQuantityField` + caption block (lines 36-41) with:

```swift
                    DoseQuantityField(
                        title: "Quantity", value: $quantity,
                        range: 0.5...20, step: 0.5,
                        max: selectedRoutine.map { DoseAllocation.remaining(medication, addingTo: $0) })
                    if let routine = selectedRoutine, let days = RecurrenceLabel.short(for: routine) {
                        Text("\(DoseFormat.qty(DoseAllocation.remaining(medication, addingTo: routine))) remaining on \(days)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let routine = selectedRoutine {
                        Text("\(DoseFormat.qty(DoseAllocation.remaining(medication, addingTo: routine))) remaining per day")
                            .font(.caption).foregroundStyle(.secondary)
                    }
```

Replace the Add-button disabled check (lines 50-53):

```swift
                    Button("Add") { add() }
                        .disabled(selectedRoutine == nil ||
                                  selectedRoutine.map {
                                      DoseAllocation.adding(quantity, to: $0, exceedsTargetFor: medication)
                                  } ?? true)
```

Replace the `onAppear` quantity seed (lines 64-66) — without a routine yet, default to 1.0:

```swift
            .onAppear { quantity = 1.0 }
```

- [ ] **Step 4: Routine-aware remaining in `RoutineEditor`**

In `RoutineDosePlanner/Views/Meds/RoutineEditor.swift`, the "add med to this routine" sheet uses the optional `routine` (the routine being edited, `nil` for a brand-new unsaved routine) and `med`. Replace the `max:` argument and caption (lines 107-112):

```swift
                        DoseQuantityField(
                            title: "Quantity", value: $addQuantity,
                            range: 0.5...20, step: 0.5,
                            max: routine.map { DoseAllocation.remaining(med, addingTo: $0) })
                        if let routine {
                            let slack = DoseFormat.qty(DoseAllocation.remaining(med, addingTo: routine))
                            let scope = RecurrenceLabel.short(for: routine).map { " on \($0)" } ?? " per day"
                            Text("\(slack) remaining\(scope)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
```

Replace the Add-button disable (line 131):

```swift
                            .disabled(routine.map { DoseAllocation.adding(addQuantity, to: $0, exceedsTargetFor: med) } ?? false)
```

- [ ] **Step 5: Progressive disclosure in `ChangeDoseSheet`**

In `RoutineDosePlanner/Views/Meds/ChangeDoseSheet.swift`:

Add state (after line 13):

```swift
    @State private var variesByDay = false
    @State private var weekdayTargets = Array(repeating: 1.0, count: 7)
```

Replace the `overAllocated` computed (lines 25-28) with a day-aware version:

```swift
    private var resolvedWeekdayTargets: [Double]? {
        variesByDay ? WeekdayDoseTargets.collapse(weekdayTargets).perWeekday : nil
    }
    private var resolvedDaily: Double {
        variesByDay ? WeekdayDoseTargets.collapse(weekdayTargets).daily : target
    }
    private var overAllocated: Bool {
        let routinesByID = Dictionary(uniqueKeysWithValues: allRoutines.map { ($0.persistentModelID, $0) })
        let placements: [(routine: Routine, quantity: Double)] = selected.compactMap { id in
            guard let routine = routinesByID[id] else { return nil }
            return (routine, quantities[id] ?? 1.0)
        }
        return DoseAllocation.placementsOverTarget(
            daily: resolvedDaily, perWeekday: resolvedWeekdayTargets, placements: placements)
    }
```

Replace the "New dose" section's dose field (lines 33-36) with the toggle + disclosure:

```swift
                Section("New dose") {
                    StrengthInputField(value: $strengthValue, unit: $strengthUnit)
                    Toggle("Amount varies by day of week", isOn: $variesByDay)
                    if variesByDay {
                        ForEach(1...7, id: \.self) { wd in
                            DoseQuantityField(
                                title: DoseSummaryFormatter.shortWeekdays[wd - 1],
                                value: Binding(
                                    get: { weekdayTargets[wd - 1] },
                                    set: { weekdayTargets[wd - 1] = $0 }),
                                range: 0...20, step: 0.5)
                        }
                    } else {
                        DoseQuantityField(title: "Doses per day", value: $target)
                    }
                }
```

Update `onAppear` (lines 60-69) to seed the disclosure state:

```swift
            .onAppear {
                strengthValue = medication.strengthValue
                strengthUnit = medication.strengthUnit
                target = medication.dailyDoseTarget
                variesByDay = medication.hasVariableSchedule
                weekdayTargets = WeekdayDoseTargets.expand(
                    daily: medication.dailyDoseTarget, perWeekday: medication.weekdayDoseTargets)
                for item in medication.routineItems ?? [] {
                    guard let routine = item.routine else { continue }
                    let id = routine.persistentModelID
                    selected.insert(id)
                    quantities[id] = item.quantity
                }
            }
```

Update `save()` to pass the resolved targets (lines 91-95):

```swift
            try MedicationService.changeDose(
                medication, newStrengthValue: strengthValue, newStrengthUnit: strengthUnit,
                newDailyDoseTarget: resolvedDaily, newWeekdayDoseTargets: resolvedWeekdayTargets,
                placements: placements, reason: reason, in: context)
```

> NOTE: `RoutineAllocationSection` still receives the scalar `target`. When `variesByDay` is on, pass `resolvedDaily` so its running-total header stays defined; the authoritative per-day check is `overAllocated`/the service. Change line 43's `target: target` to `target: resolvedDaily`.

- [ ] **Step 6: Progressive disclosure in `MedicationEditor` (add flow)**

In `RoutineDosePlanner/Views/Meds/MedicationEditor.swift`:

Add state after line 30 (`@State private var errorMessage`):

```swift
    @State private var variesByDay = false
    @State private var weekdayTargets = Array(repeating: 1.0, count: 7)
```

Replace the `assignedTotal` and `saveBlocked` computeds (lines 37-44) with resolved targets + a day-aware block check (`assignedTotal` is no longer used):

```swift
    private var resolvedWeekdayTargets: [Double]? {
        variesByDay ? WeekdayDoseTargets.collapse(weekdayTargets).perWeekday : nil
    }
    private var resolvedDaily: Double {
        variesByDay ? WeekdayDoseTargets.collapse(weekdayTargets).daily : dailyDoseTarget
    }
    private var saveBlocked: Bool {
        guard isAdd, !isPRN else { return false }
        if resolvedWeekdayTargets == nil && resolvedDaily <= 0 { return true }
        let placements = routines
            .filter { selected.contains($0.persistentModelID) }
            .map { (routine: $0, quantity: quantities[$0.persistentModelID] ?? 1.0) }
        return DoseAllocation.placementsOverTarget(
            daily: resolvedDaily, perWeekday: resolvedWeekdayTargets, placements: placements)
    }
```

Replace the dose-target field block (lines 56-58) with the toggle + disclosure:

```swift
                    if isAdd && !isPRN {
                        Toggle("Amount varies by day of week", isOn: $variesByDay)
                        if variesByDay {
                            ForEach(1...7, id: \.self) { wd in
                                DoseQuantityField(
                                    title: DoseSummaryFormatter.shortWeekdays[wd - 1],
                                    value: Binding(
                                        get: { weekdayTargets[wd - 1] },
                                        set: { weekdayTargets[wd - 1] = $0 }),
                                    range: 0...20, step: 0.5)
                            }
                        } else {
                            DoseQuantityField(title: "Doses per day", value: $dailyDoseTarget)
                        }
                    }
```

Change the `RoutineAllocationSection` target argument (line 68) to `target: resolvedDaily`.

Update the `addMedication` call in `save()` (lines 119-122) to pass the resolved targets:

```swift
                try MedicationService.addMedication(
                    name: name, strengthValue: strengthValue, strengthUnit: strengthUnit, form: form,
                    isPRN: isPRN, notes: notes, dailyDoseTarget: resolvedDaily,
                    weekdayDoseTargets: resolvedWeekdayTargets, placements: placements,
                    reason: reason, in: context)
```

Do not change the `.edit` mode handling in `save()` or `load()`.

- [ ] **Step 7: Build and verify**

Run: `xcodebuild build -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED.

Manual verification (simulator): create a med, toggle "Amount varies by day of week", set Thu = 1 and Sat = 2, add it to a Thursday routine (qty 1) and a Saturday routine (qty 2), and confirm the detail view shows `Thu 1 · Sat 2 · 3 tablet/wk` with no amber caution. Set Saturday's scheduled qty to 1 and confirm the caution reads `Sat: 1 of 2 tablet`.

- [ ] **Step 8: Commit**

```bash
git add RoutineDosePlanner/Views/Meds
git commit -m "Wire per-weekday targets into med detail, editors, and capacity captions"
```

---

## Task 8: Remove dead scalar allocation API

Now that all call sites use the day-aware API, remove the obsolete scalar methods.

**Files:**
- Modify: `RoutineDosePlanner/Services/DoseAllocation.swift`
- Test: `RoutineDosePlannerTests/MedicationServiceTests.swift` (assertions that referenced `DoseAllocation.allocated`)

- [ ] **Step 1: Find remaining references**

Run: `grep -rn "DoseAllocation.allocated\|DoseAllocation.remaining(\|allocatedStrength\|targetStrength" RoutineDosePlanner RoutineDosePlannerTests`
Expected: matches only in `DoseAllocation.swift` (definitions) and a few `MedicationServiceTests` assertions like `#expect(DoseAllocation.allocated(med) == 1.5)`. (Note: `remaining(_:addingTo:)` calls contain a comma so the `remaining(` grep with no comma won't match them — verify any hits are the scalar one-arg form.)

- [ ] **Step 2: Update the test assertions**

In `RoutineDosePlannerTests/MedicationServiceTests.swift`, replace each scalar assertion with a routine-item sum. For example, `#expect(DoseAllocation.allocated(med) == 1.5)` becomes:

```swift
        #expect((med.routineItems ?? []).reduce(0) { $0 + $1.quantity } == 1.5)
```

Apply to the three occurrences (`testAddToRoutineWithinRemainingInserts`, `testMoveToRoutinePreservesQuantityAndWritesOldNewEvent`, and any other). Search to be exhaustive.

- [ ] **Step 3: Delete the scalar methods**

In `RoutineDosePlanner/Services/DoseAllocation.swift`, delete `allocated(_:)` (lines 11-13), the scalar `remaining(_:)` (lines 16-18), `allocatedStrength(_:)` and `targetStrength(_:)` (lines 34-41). Keep `Status`, `tolerance`, `isOverTarget`, `scheduledByWeekday`, `status`, `remaining(_:addingTo:)`, `adding(...)`, `placementsOverTarget`, `moving`, and `needsAttention`.

- [ ] **Step 4: Build and run the full test suite**

Run: `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED and all suites PASS. If any file still references a deleted method, the compiler will name it — fix that call site to the day-aware equivalent.

- [ ] **Step 5: Commit**

```bash
git add RoutineDosePlanner/Services/DoseAllocation.swift RoutineDosePlannerTests/MedicationServiceTests.swift
git commit -m "Remove obsolete scalar dose-allocation API"
```

---

## Final verification

- [ ] **Run the full suite once more**

Run: `xcodebuild test -scheme RoutineDosePlanner -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: all tests pass, BUILD SUCCEEDED.

- [ ] **Confirm the motivating scenario end-to-end** (covered by `DoseAllocationTests.variableScheduleMatchingTargetsIsFull` and `MedicationServiceTests.testAddToRoutineAllowsSameQuantityOnNonOverlappingDays`): a med taking 1 on Thursday and 2 on Saturday reports `.full`, not `.over`.
