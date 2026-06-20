# Session 3 — Reminders & Live Activities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PillDaddy prompt on its own — a scheduled per-batch reminder lifecycle (heads-up → due → escalating follow-ups), a local Live Activity that pesters until logged, persisted `missed` doses at the grace cutoff, and a Settings tab to tune it.

**Architecture:** All decision logic lives in pure, unit-tested functions (`ReminderScheduler.plan`, `ReminderTier`, `DoseLogService.materializeMissed` + `MissedReconciler`); thin side-effecting layers wrap `UNUserNotificationCenter` and ActivityKit. A new `PillDaddyWidgets` app-extension target hosts the Live Activity UI, sharing one `ActivityAttributes` source file with the app. No APNs / push entitlement is added — device signing is preserved (CloudKit-only entitlements stay as-is). Notification taps and Live Activity `widgetURL`s deep-link into the Today tab via a shared `AppRouter`.

**Tech Stack:** SwiftUI, SwiftData (iOS 26 deployment target), UserNotifications, ActivityKit, WidgetKit, XcodeGen, XCTest.

---

## Reference: established patterns

- Tests use `ModelTestSupport.makeContainer()` (in-memory `PillDaddySchema`) and run `@MainActor`. See `PillDaddyTests/DoseLogServiceTests.swift`.
- Services are `@MainActor enum`s with static methods taking a `ModelContext`. See `PillDaddy/Services/DoseLogService.swift`.
- Recurrence + slot-time helpers already exist: `DayQuery.recurs(_:on:)`, `DayQuery.slotDate(for:on:)`, `DayQuery.batchDays(from:on:)`. **Reuse them — do not re-implement.**
- `xcodegen generate` regenerates the Xcode project and the app/extension `Info.plist`s from `project.yml`. After editing `project.yml`, always run it.
- Build/test command used throughout:

```bash
xcodebuild -project PillDaddy.xcodeproj -scheme PillDaddy \
  -destination 'platform=iOS Simulator,name=iPhone 16' build test 2>&1 | tail -30
```

(If `iPhone 16` is unavailable, run `xcrun simctl list devices available` and substitute an available iOS 26 simulator name.)

---

## Task 1: Add a stable `uuid` to `Batch`

A batch needs a process-stable string identifier to key notifications, cancel a slot's follow-ups, and carry through a Live Activity `widgetURL`. `PersistentIdentifier` is not suitable across the app/extension boundary; add a `UUID`.

**Files:**
- Modify: `PillDaddy/Models/Batch.swift`
- Test: `PillDaddyTests/BatchRelationshipTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append to `PillDaddyTests/BatchRelationshipTests.swift` (inside the existing `final class BatchRelationshipTests`):

```swift
    func testBatchHasStableDistinctUUID() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        let a = Batch(name: "A")
        let b = Batch(name: "B")
        context.insert(a); context.insert(b)
        try context.save()
        XCTAssertNotEqual(a.uuid, b.uuid)
        let savedID = a.uuid
        XCTAssertEqual(a.uuid, savedID)   // stable across access
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the build/test command above. Expected: compile failure — `value of type 'Batch' has no member 'uuid'`.

- [ ] **Step 3: Add the property**

In `PillDaddy/Models/Batch.swift`, add the stored property after `var sortOrder: Int = 0`:

```swift
    var uuid: UUID = UUID()
```

It has a default value, so it is CloudKit-safe (additive, no migration prompt). Leave the initializer as-is — `uuid` keeps its default for every existing call site.

- [ ] **Step 4: Run test to verify it passes**

Run the build/test command. Expected: PASS (whole suite still green).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Models/Batch.swift PillDaddyTests/BatchRelationshipTests.swift
git commit -m "feat: add stable uuid to Batch for reminder identity"
```

---

## Task 2: `ReminderSettings` (UserDefaults-backed)

A single source of truth for the master toggle, grace window, and heads-up toggle, readable by both views and services.

**Files:**
- Create: `PillDaddy/Models/ReminderSettings.swift`
- Test: `PillDaddyTests/ReminderSettingsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/ReminderSettingsTests.swift`:

```swift
import XCTest
@testable import PillDaddy

@MainActor
final class ReminderSettingsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaults() {
        let s = ReminderSettings(defaults: freshDefaults())
        XCTAssertTrue(s.remindersEnabled)
        XCTAssertEqual(s.graceMinutes, 120)
        XCTAssertTrue(s.headsUpEnabled)
    }

    func testPersistsChanges() {
        let d = freshDefaults()
        let s = ReminderSettings(defaults: d)
        s.remindersEnabled = false
        s.graceMinutes = 60
        s.headsUpEnabled = false
        let reloaded = ReminderSettings(defaults: d)
        XCTAssertFalse(reloaded.remindersEnabled)
        XCTAssertEqual(reloaded.graceMinutes, 60)
        XCTAssertFalse(reloaded.headsUpEnabled)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the build/test command. Expected: compile failure — `cannot find 'ReminderSettings' in scope`.

- [ ] **Step 3: Write the implementation**

Create `PillDaddy/Models/ReminderSettings.swift`:

```swift
import Foundation
import Observation

/// Single source of truth for reminder preferences, backed by UserDefaults so
/// both views and services read the same values. Not `@MainActor` so it can be a
/// default-initialized stored property of the (nonisolated) `App`/`AppDelegate`;
/// UserDefaults is thread-safe and all mutations happen from the main thread.
@Observable
final class ReminderSettings {
    private let defaults: UserDefaults

    private enum Key {
        static let enabled = "reminders.enabled"
        static let grace = "reminders.graceMinutes"
        static let headsUp = "reminders.headsUpEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.grace: 120,
            Key.headsUp: true,
        ])
    }

    var remindersEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var graceMinutes: Int {
        get { defaults.integer(forKey: Key.grace) }
        set { defaults.set(newValue, forKey: Key.grace) }
    }

    var headsUpEnabled: Bool {
        get { defaults.bool(forKey: Key.headsUp) }
        set { defaults.set(newValue, forKey: Key.headsUp) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the build/test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Models/ReminderSettings.swift PillDaddyTests/ReminderSettingsTests.swift
git commit -m "feat: ReminderSettings UserDefaults-backed preferences"
```

---

## Task 3: `ReminderTier` (shared, pure escalation logic)

A 3-stage escalation tier computed from elapsed time vs the grace window. Lives in a **shared** file because both the app and the widget extension need it.

**Files:**
- Create: `PillDaddy/Shared/PillReminderAttributes.swift` (tier only for now; attributes added in Task 7)
- Test: `PillDaddyTests/ReminderTierTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/ReminderTierTests.swift`:

```swift
import XCTest
@testable import PillDaddy

final class ReminderTierTests: XCTestCase {

    func testTierThresholds() {
        let grace: TimeInterval = 120 * 60
        // calm: < 1/3 of grace (< 40 min)
        XCTAssertEqual(ReminderTier.forElapsed(0, grace: grace), .calm)
        XCTAssertEqual(ReminderTier.forElapsed(39 * 60, grace: grace), .calm)
        // overdue: 1/3 .. 3/4 (40 .. 90 min)
        XCTAssertEqual(ReminderTier.forElapsed(45 * 60, grace: grace), .overdue)
        XCTAssertEqual(ReminderTier.forElapsed(89 * 60, grace: grace), .overdue)
        // urgent: >= 3/4 (>= 90 min)
        XCTAssertEqual(ReminderTier.forElapsed(107 * 60, grace: grace), .urgent)
        XCTAssertEqual(ReminderTier.forElapsed(130 * 60, grace: grace), .urgent)
    }

    func testNegativeElapsedIsCalm() {
        XCTAssertEqual(ReminderTier.forElapsed(-60, grace: 7200), .calm)
    }

    func testZeroGraceIsUrgent() {
        XCTAssertEqual(ReminderTier.forElapsed(0, grace: 0), .urgent)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the build/test command. Expected: compile failure — `cannot find 'ReminderTier' in scope`.

- [ ] **Step 3: Write the implementation**

Create `PillDaddy/Shared/PillReminderAttributes.swift`:

```swift
import Foundation

/// Escalation stage for an overdue batch, derived from how far through the grace
/// window the dose is. Pure + shared between the app and the widget extension.
enum ReminderTier: String, Codable, Hashable {
    case calm     // freshly due
    case overdue  // visibly late
    case urgent   // close to being marked missed

    static func forElapsed(_ elapsed: TimeInterval, grace: TimeInterval) -> ReminderTier {
        guard grace > 0 else { return .urgent }
        let fraction = elapsed / grace
        switch fraction {
        case ..<(1.0 / 3.0): return .calm
        case ..<(3.0 / 4.0): return .overdue
        default: return .urgent
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the build/test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Shared/PillReminderAttributes.swift PillDaddyTests/ReminderTierTests.swift
git commit -m "feat: ReminderTier escalation logic (shared, pure)"
```

---

## Task 4: `ReminderScheduler.plan` (pure notification planner)

The core scheduling decision: given batches, settings, `now`, and a horizon, produce the exact set of notifications to schedule. No `UNUserNotificationCenter` here — pure and fully tested.

**Files:**
- Create: `PillDaddy/Services/ReminderScheduler.swift`
- Test: `PillDaddyTests/ReminderSchedulerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PillDaddyTests/ReminderSchedulerTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class ReminderSchedulerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var cal: Calendar { Calendar.current }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil; container = nil
        try await super.tearDown()
    }

    /// A daily batch at the given clock time with one active scheduled med.
    private func makeBatch(hour: Int, minute: Int = 0,
                           recurrence: RecurrenceKind = .daily, weekdays: [Int]? = nil) -> Batch {
        let t = cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
        let batch = Batch(name: "B\(hour)", timeOfDay: t,
                          recurrenceKind: recurrence, weekdays: weekdays)
        context.insert(batch)
        let med = Medication(name: "Med\(hour)")
        context.insert(med)
        context.insert(BatchItem(quantity: 1.0, medication: med, batch: batch))
        try? context.save()
        return batch
    }

    /// `now` set to 1 hour before the batch slot today, so all reminders are in the future.
    private func nowBefore(_ batch: Batch) -> Date {
        DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(-3600)
    }

    func testDailyBatchEmitsHeadsUpDueAndThreeFollowUps() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        let kinds = plan.map(\.kind).sorted { $0.rawValue < $1.rawValue }
        XCTAssertEqual(plan.count, 5)   // headsUp + due + 3 follow-ups (30/60/90)
        XCTAssertEqual(kinds.filter { $0 == .headsUp }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .due }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .followUp }.count, 3)
    }

    func testHeadsUpDisabledDropsHeadsUp() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: false, masterEnabled: true)
        XCTAssertFalse(plan.contains { $0.kind == .headsUp })
        XCTAssertEqual(plan.count, 4)
    }

    func testFollowUpsClippedToGraceWindow() {
        let batch = makeBatch(hour: 9)
        // 60-minute grace → only the +30 follow-up is strictly before the cutoff.
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 60, headsUpEnabled: true, masterEnabled: true)
        XCTAssertEqual(plan.filter { $0.kind == .followUp }.count, 1)
    }

    func testMasterDisabledEmitsNothing() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: false)
        XCTAssertTrue(plan.isEmpty)
    }

    func testPastFireDatesAreOmitted() {
        let batch = makeBatch(hour: 9)
        // now = slot + 40 min → headsUp, due, +30 are in the past; only +60, +90 remain.
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(40 * 60)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: now, horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now })
        XCTAssertEqual(plan.filter { $0.kind == .followUp }.count, 2)
    }

    func testWeekdayBatchAbsentOnExcludedDay() {
        let today = cal.component(.weekday, from: .now)
        let other = (today % 7) + 1   // a different weekday
        let batch = makeBatch(hour: 9, recurrence: .weekdays, weekdays: [other])
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        XCTAssertTrue(plan.isEmpty)
    }

    func testCompletedSlotIsSkipped() {
        let batch = makeBatch(hour: 9)
        let slot = DayQuery.slotDate(for: batch, on: .now)
        let key = ReminderScheduler.slotKey(batchUUID: batch.uuid.uuidString, slot: slot)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true,
            completedSlots: [key])
        XCTAssertTrue(plan.isEmpty)
    }

    func testRespectsLimit() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true, limit: 2)
        XCTAssertEqual(plan.count, 2)
        // earliest fire dates kept
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    func testIdentifiersAreUnique() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the build/test command. Expected: compile failure — `cannot find 'ReminderScheduler' in scope`.

- [ ] **Step 3: Write the implementation**

Create `PillDaddy/Services/ReminderScheduler.swift`:

```swift
import Foundation
import SwiftData

enum ReminderKind: String, CaseIterable {
    case headsUp, due, followUp
}

/// Plans (and applies) the per-batch notification lifecycle. The `plan` function is
/// pure and unit-tested; `reschedule` is the thin UNUserNotificationCenter layer.
@MainActor
enum ReminderScheduler {

    /// Offsets (minutes after the slot) at which "still due" follow-ups fire.
    static let followUpOffsets = [30, 60, 90]

    struct Planned: Equatable {
        let identifier: String
        let batchUUID: String
        let fireDate: Date
        let kind: ReminderKind
        let title: String
        let body: String
    }

    /// Stable per-slot key used to skip already-logged batches.
    static func slotKey(batchUUID: String, slot: Date) -> String {
        "\(batchUUID)|\(Int(slot.timeIntervalSince1970))"
    }

    /// The notifications to schedule across `horizonDays` starting at `now`'s day.
    /// Pure: no side effects, deterministic for fixed inputs.
    static func plan(
        batches: [Batch],
        now: Date,
        horizonDays: Int,
        graceMinutes: Int,
        headsUpEnabled: Bool,
        masterEnabled: Bool,
        completedSlots: Set<String> = [],
        limit: Int = 64
    ) -> [Planned] {
        guard masterEnabled else { return [] }
        let cal = Calendar.current
        var result: [Planned] = []

        for offset in 0..<max(horizonDays, 0) {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            for batch in batches where DayQuery.recurs(batch, on: day) {
                let medCount = activeMedCount(batch)
                guard medCount > 0 else { continue }
                let slot = DayQuery.slotDate(for: batch, on: day)
                let key = slotKey(batchUUID: batch.uuid.uuidString, slot: slot)
                guard !completedSlots.contains(key) else { continue }

                if headsUpEnabled {
                    result.append(make(batch, slot: slot, kind: .headsUp,
                                       offsetMinutes: -15, medCount: medCount))
                }
                result.append(make(batch, slot: slot, kind: .due,
                                   offsetMinutes: 0, medCount: medCount))
                for m in followUpOffsets where m < graceMinutes {
                    result.append(make(batch, slot: slot, kind: .followUp,
                                       offsetMinutes: m, medCount: medCount))
                }
            }
        }

        return result
            .filter { $0.fireDate > now }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(limit)
            .map { $0 }
    }

    private static func activeMedCount(_ batch: Batch) -> Int {
        (batch.items ?? []).filter {
            ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false)
        }.count
    }

    private static func make(_ batch: Batch, slot: Date, kind: ReminderKind,
                             offsetMinutes: Int, medCount: Int) -> Planned {
        let fire = slot.addingTimeInterval(TimeInterval(offsetMinutes) * 60)
        let meds = "\(medCount) med\(medCount == 1 ? "" : "s")"
        let title: String
        let body: String
        switch kind {
        case .headsUp:
            title = "\(batch.name) coming up"
            body = "\(meds) due in 15 minutes"
        case .due:
            title = "\(batch.name) is due"
            body = "Time for \(meds)"
        case .followUp:
            title = "\(batch.name) still due"
            body = "\(meds) not logged yet"
        }
        let id = "\(batch.uuid.uuidString)|\(Int(slot.timeIntervalSince1970))|\(kind.rawValue)|\(offsetMinutes)"
        return Planned(identifier: id, batchUUID: batch.uuid.uuidString,
                       fireDate: fire, kind: kind, title: title, body: body)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the build/test command. Expected: PASS (all `ReminderSchedulerTests`).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/ReminderScheduler.swift PillDaddyTests/ReminderSchedulerTests.swift
git commit -m "feat: ReminderScheduler.plan pure notification planner"
```

---

## Task 5: `ReminderScheduler` apply layer + completed-slot helper

Wrap the pure plan with `UNUserNotificationCenter` (cancel-all then re-add) and a helper that finds fully-logged slots to skip. Side-effecting → build-verified, not unit-tested.

**Files:**
- Modify: `PillDaddy/Services/ReminderScheduler.swift`

- [ ] **Step 1: Add the apply layer and helper**

Add `import UserNotifications` at the top of `PillDaddy/Services/ReminderScheduler.swift`, then append these methods inside the `ReminderScheduler` enum:

```swift
    /// Keys for batch slots in the horizon that are already fully logged (state == .taken),
    /// so the scheduler can skip pestering for them.
    static func completedSlotKeys(batches: [Batch], now: Date, horizonDays: Int) -> Set<String> {
        let cal = Calendar.current
        var keys: Set<String> = []
        for offset in 0..<max(horizonDays, 0) {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            for bd in DayQuery.batchDays(from: batches, on: day) where bd.state == .taken {
                keys.insert(slotKey(batchUUID: bd.batch.uuid.uuidString, slot: bd.slotDate))
            }
        }
        return keys
    }

    /// Rebuilds the pending-notification set: removes all pending requests and re-adds
    /// the current plan. Called on launch/foreground, after logging, and on settings change.
    static func reschedule(
        batches: [Batch],
        settings: ReminderSettings,
        now: Date = .now,
        horizonDays: Int = 3,
        completedSlots: Set<String>,
        center: UNUserNotificationCenter = .current()
    ) {
        let planned = plan(
            batches: batches, now: now, horizonDays: horizonDays,
            graceMinutes: settings.graceMinutes,
            headsUpEnabled: settings.headsUpEnabled,
            masterEnabled: settings.remindersEnabled,
            completedSlots: completedSlots)

        center.removeAllPendingNotificationRequests()
        let cal = Calendar.current
        for p in planned {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            content.userInfo = ["batchUUID": p.batchUUID]
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: p.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: p.identifier, content: content, trigger: trigger))
        }
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: BUILD SUCCEEDS, existing tests still PASS.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Services/ReminderScheduler.swift
git commit -m "feat: ReminderScheduler apply layer + completed-slot helper"
```

---

## Task 6: Missed-dose materialization

At the grace cutoff, write `missed` `DoseLog`s for un-logged scheduled meds. Reuses the Session 2 upsert key for idempotency.

**Files:**
- Modify: `PillDaddy/Services/DoseLogService.swift`
- Create: `PillDaddy/Services/MissedReconciler.swift`
- Test: `PillDaddyTests/MissedReconcilerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PillDaddyTests/MissedReconcilerTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MissedReconcilerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var cal: Calendar { Calendar.current }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil; container = nil
        try await super.tearDown()
    }

    @discardableResult
    private func makeBatch(hour: Int, recurrence: RecurrenceKind = .daily,
                           weekdays: [Int]? = nil) -> (Batch, BatchItem) {
        let t = cal.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        let batch = Batch(name: "B\(hour)", timeOfDay: t,
                          recurrenceKind: recurrence, weekdays: weekdays)
        context.insert(batch)
        let med = Medication(name: "Med\(hour)")
        context.insert(med)
        let item = BatchItem(quantity: 1.0, medication: med, batch: batch)
        context.insert(item)
        try? context.save()
        return (batch, item)
    }

    private func logs() throws -> [DoseLog] { try context.fetch(FetchDescriptor<DoseLog>()) }

    func testWritesMissedForUnloggedSlotPastGrace() throws {
        let (batch, _) = makeBatch(hour: 9)
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, in: context)
        let all = try logs()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, DoseStatus.missed.rawValue)
        XCTAssertNil(all.first?.takenAt)
        XCTAssertEqual(all.first?.snapshotMedName, "Med9")
    }

    func testDoesNotWriteBeforeGrace() throws {
        let (batch, _) = makeBatch(hour: 9)
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(60 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, in: context)
        XCTAssertEqual(try logs().count, 0)
    }

    func testPreservesExistingTakenOrSkipped() throws {
        let (batch, item) = makeBatch(hour: 9)
        DoseLogService.logBatchTaken(batch, on: .now, items: [item], takenAt: .now, note: "", in: context)
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, in: context)
        let all = try logs()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, DoseStatus.taken.rawValue)
    }

    func testIdempotent() throws {
        let (batch, _) = makeBatch(hour: 9)
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, in: context)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, in: context)
        XCTAssertEqual(try logs().count, 1)
    }

    func testExcludesDiscontinuedMed() throws {
        let (batch, item) = makeBatch(hour: 9)
        item.medication?.isActive = false
        try context.save()
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, in: context)
        XCTAssertEqual(try logs().count, 0)
    }

    func testRespectsWeekdayRecurrence() throws {
        let today = cal.component(.weekday, from: .now)
        let other = (today % 7) + 1
        let (batch, _) = makeBatch(hour: 9, recurrence: .weekdays, weekdays: [other])
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, in: context)
        XCTAssertEqual(try logs().count, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the build/test command. Expected: compile failure — `cannot find 'MissedReconciler'` and `materializeMissed`.

- [ ] **Step 3: Add `materializeMissed` to `DoseLogService`**

In `PillDaddy/Services/DoseLogService.swift`, add this method inside the `enum DoseLogService` (after `revertBatch`, before `// MARK: - PRN`):

```swift
    /// Writes a `missed` row for the item's slot on `day` only if nothing is logged
    /// there yet (never overwrites a taken/skipped dose). Idempotent.
    static func materializeMissed(_ item: BatchItem, on day: Date, in context: ModelContext) {
        guard existingLog(for: item, on: day) == nil else { return }
        upsert(item: item, on: day, status: .missed, takenAt: nil, note: "", in: context)
        try? context.save()
    }
```

(`existingLog(for:on:)` and `upsert(...)` already exist as private members of the same enum.)

- [ ] **Step 4: Create `MissedReconciler`**

Create `PillDaddy/Services/MissedReconciler.swift`:

```swift
import Foundation
import SwiftData

/// Sweeps past batch slots whose grace window has elapsed and materializes `missed`
/// DoseLogs for any med that was never logged. Runs on app launch/foreground.
@MainActor
enum MissedReconciler {

    static func reconcile(
        batches: [Batch],
        now: Date,
        graceMinutes: Int,
        lookbackDays: Int = 7,
        in context: ModelContext
    ) {
        let cal = Calendar.current
        let grace = TimeInterval(graceMinutes) * 60
        for offset in 0...max(lookbackDays, 0) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            for bd in DayQuery.batchDays(from: batches, on: day) {
                let cutoff = bd.slotDate.addingTimeInterval(grace)
                guard now >= cutoff else { continue }
                for med in bd.meds where med.log == nil {
                    DoseLogService.materializeMissed(med.item, on: day, in: context)
                }
            }
        }
    }
}
```

`DayQuery.batchDays` already excludes discontinued/PRN meds and honors recurrence, so those cases are handled.

- [ ] **Step 5: Run tests to verify they pass**

Run the build/test command. Expected: PASS (all `MissedReconcilerTests`, existing suites green).

- [ ] **Step 6: Commit**

```bash
git add PillDaddy/Services/DoseLogService.swift PillDaddy/Services/MissedReconciler.swift PillDaddyTests/MissedReconcilerTests.swift
git commit -m "feat: missed-dose materialization at grace cutoff"
```

---

## Task 7: Live Activity attributes (shared contract)

Define the `ActivityAttributes` carried between the app and widget. Append to the shared file from Task 3.

**Files:**
- Modify: `PillDaddy/Shared/PillReminderAttributes.swift`

- [ ] **Step 1: Append the attributes**

Add to the top of `PillDaddy/Shared/PillReminderAttributes.swift`:

```swift
import ActivityKit
```

Then append at the end of the file:

```swift
/// Describes one overdue/due batch surfaced as a Live Activity.
struct PillReminderAttributes: ActivityAttributes {
    /// Static for the life of the activity.
    let batchID: String       // Batch.uuid.uuidString
    let batchName: String
    let colorHex: String
    let medCount: Int

    /// Dynamic, updated as time passes.
    struct ContentState: Codable, Hashable {
        let scheduledDate: Date   // batch slot time
        let graceEndDate: Date    // when it becomes "missed"
        let tier: ReminderTier
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: BUILD SUCCEEDS, tests still PASS.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Shared/PillReminderAttributes.swift
git commit -m "feat: PillReminderAttributes Live Activity contract"
```

---

## Task 8: Widget-extension target + Live Activity UI

Create the `PillDaddyWidgets` app-extension target, wire it in `project.yml`, embed it in the app, and build the Lock Screen + Dynamic Island UI. The shared attributes file is compiled into both targets.

**Files:**
- Create: `PillDaddyWidgets/PillDaddyWidgetsBundle.swift`
- Create: `PillDaddyWidgets/PillReminderLiveActivity.swift`
- Modify: `project.yml`

- [ ] **Step 1: Create the widget bundle**

Create `PillDaddyWidgets/PillDaddyWidgetsBundle.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct PillDaddyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PillReminderLiveActivity()
    }
}
```

- [ ] **Step 2: Create the Live Activity UI**

Create `PillDaddyWidgets/PillReminderLiveActivity.swift`:

```swift
import ActivityKit
import WidgetKit
import SwiftUI

struct PillReminderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PillReminderAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Circle().fill(accent(context.state.tier)).frame(width: 26, height: 26)
                        .overlay(Image(systemName: icon(context.state.tier)).font(.caption2).foregroundStyle(.white))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.batchName).font(.headline)
                        Text("\(context.attributes.medCount) meds · tap to log")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.scheduledDate...context.state.graceEndDate,
                         countsDown: false)
                        .font(.system(.title3, design: .rounded)).monospacedDigit()
                        .foregroundStyle(accent(context.state.tier))
                        .frame(maxWidth: 64)
                }
            } compactLeading: {
                Circle().fill(accent(context.state.tier)).frame(width: 12, height: 12)
            } compactTrailing: {
                Text(timerInterval: context.state.scheduledDate...context.state.graceEndDate,
                     countsDown: false)
                    .monospacedDigit().frame(maxWidth: 44)
                    .foregroundStyle(accent(context.state.tier))
            } minimal: {
                Circle().fill(accent(context.state.tier)).frame(width: 12, height: 12)
            }
            .widgetURL(URL(string: "pilldaddy://batch/\(context.attributes.batchID)"))
        }
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<PillReminderAttributes>) -> some View {
        let tier = context.state.tier
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon(tier))
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(accent(tier), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(tier, name: context.attributes.batchName))
                        .font(.headline).foregroundStyle(.white)
                    Text("\(context.attributes.medCount) meds")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text(timerInterval: context.state.scheduledDate...context.state.graceEndDate,
                     countsDown: false)
                    .font(.system(.title3, design: .rounded)).monospacedDigit()
                    .foregroundStyle(accent(tier))
            }
            ProgressView(timerInterval: context.state.scheduledDate...context.state.graceEndDate,
                         countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(accent(tier))
        }
        .padding(14)
        .widgetURL(URL(string: "pilldaddy://batch/\(context.attributes.batchID)"))
    }

    private func accent(_ tier: ReminderTier) -> Color {
        switch tier {
        case .calm: return Color(red: 0.23, green: 0.51, blue: 0.96)   // blue
        case .overdue: return Color(red: 0.96, green: 0.62, blue: 0.04) // amber
        case .urgent: return Color(red: 0.94, green: 0.27, blue: 0.27)  // red
        }
    }

    private func icon(_ tier: ReminderTier) -> String {
        switch tier {
        case .calm: return "pills.fill"
        case .overdue: return "clock.fill"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }

    private func title(_ tier: ReminderTier, name: String) -> String {
        switch tier {
        case .calm: return "\(name) is due"
        case .overdue: return "\(name) still due"
        case .urgent: return "\(name) overdue"
        }
    }
}
```

- [ ] **Step 3: Wire the target in `project.yml`**

In `project.yml`, add the new target under `targets:` (sibling of `PillDaddy` and `PillDaddyTests`):

```yaml
  PillDaddyWidgets:
    type: app-extension
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - PillDaddyWidgets
      - path: PillDaddy/Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pilldaddy.PillDaddy.widgets
    info:
      path: PillDaddyWidgets/Info.plist
      properties:
        CFBundleDisplayName: PillDaddy Reminders
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

Then add the embed dependency to the `PillDaddy` app target. Under `targets: > PillDaddy:`, add a `dependencies:` key (the app target currently has none):

```yaml
    dependencies:
      - target: PillDaddyWidgets
        embed: true
```

- [ ] **Step 4: Regenerate and build**

Run:

```bash
xcodegen generate
```

Expected: "Created project at PillDaddy.xcodeproj". Then run the build/test command. Expected: BUILD SUCCEEDS for both `PillDaddy` and `PillDaddyWidgets`; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add project.yml PillDaddyWidgets
git commit -m "feat: PillDaddyWidgets extension with Live Activity UI"
```

---

## Task 9: `LiveActivityController`

Decide the focus batch and start/update/end the single Live Activity. Side-effecting (ActivityKit) → build-verified.

**Files:**
- Create: `PillDaddy/Services/LiveActivityController.swift`

- [ ] **Step 1: Write the implementation**

Create `PillDaddy/Services/LiveActivityController.swift`:

```swift
import Foundation
import SwiftData
import ActivityKit

/// Manages a single Live Activity for the most urgent due/overdue batch today.
/// Local-only: starts/updates only while the app is foregrounded (no push).
@MainActor
enum LiveActivityController {

    /// Reconciles the running activity with the current state. Ends it when no batch
    /// is in its pester window, or starts/updates it for the focus batch.
    static func refresh(batches: [Batch], now: Date, graceMinutes: Int, enabled: Bool) {
        let running = Activity<PillReminderAttributes>.activities

        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll(running)
            return
        }

        let grace = TimeInterval(graceMinutes) * 60
        guard let focus = focusBatch(batches: batches, now: now, grace: grace) else {
            endAll(running)
            return
        }

        let slot = DayQuery.slotDate(for: focus, on: now)
        let graceEnd = slot.addingTimeInterval(grace)
        let tier = ReminderTier.forElapsed(now.timeIntervalSince(slot), grace: grace)
        let state = PillReminderAttributes.ContentState(
            scheduledDate: slot, graceEndDate: graceEnd, tier: tier)
        let content = ActivityContent(state: state, staleDate: graceEnd)

        if let existing = running.first(where: { $0.attributes.batchID == focus.uuid.uuidString }) {
            Task { await existing.update(content) }
            // end any other stale activities
            for a in running where a.attributes.batchID != focus.uuid.uuidString {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
        } else {
            endAll(running)
            let attributes = PillReminderAttributes(
                batchID: focus.uuid.uuidString, batchName: focus.name,
                colorHex: focus.colorHex, medCount: activeMedCount(focus))
            _ = try? Activity.request(attributes: attributes, content: content)
        }
    }

    /// Earliest batch today whose slot is in the pester window [slot, slot+grace)
    /// and is not fully logged.
    private static func focusBatch(batches: [Batch], now: Date, grace: TimeInterval) -> Batch? {
        DayQuery.batchDays(from: batches, on: now)
            .filter { $0.state != .taken }
            .filter { now >= $0.slotDate && now < $0.slotDate.addingTimeInterval(grace) }
            .min { $0.slotDate < $1.slotDate }?
            .batch
    }

    private static func activeMedCount(_ batch: Batch) -> Int {
        (batch.items ?? []).filter {
            ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false)
        }.count
    }

    private static func endAll(_ running: [Activity<PillReminderAttributes>]) {
        for a in running { Task { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: BUILD SUCCEEDS, tests PASS.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Services/LiveActivityController.swift
git commit -m "feat: LiveActivityController start/update/end focus batch"
```

---

## Task 10: `AppRouter` + `ReminderSync` + Info.plist additions

A shared navigation-intent object, a small façade that both the app and Settings call to re-sync, and the Info.plist keys for Live Activities + the deep-link URL scheme.

**Files:**
- Create: `PillDaddy/Services/AppRouter.swift`
- Create: `PillDaddy/Services/ReminderSync.swift`
- Modify: `project.yml`

- [ ] **Step 1: Create `AppRouter`**

Create `PillDaddy/Services/AppRouter.swift`:

```swift
import Foundation
import Observation

/// Holds a pending deep-link navigation intent (a batch to focus on the Today tab).
/// Set by the notification delegate and the Live Activity widgetURL handler.
/// Not `@MainActor` so `AppDelegate` can default-initialize it as a stored property;
/// all mutations happen on the main thread.
@Observable
final class AppRouter {
    var pendingBatchUUID: String?
}
```

- [ ] **Step 2: Create `ReminderSync`**

Create `PillDaddy/Services/ReminderSync.swift`:

```swift
import Foundation
import SwiftData

/// Single entry point for re-syncing notifications + the Live Activity to current
/// state. Called on foreground, after logging, and on settings changes.
@MainActor
enum ReminderSync {
    static let horizonDays = 3

    static func refresh(context: ModelContext, settings: ReminderSettings, now: Date = .now) {
        let batches = (try? context.fetch(FetchDescriptor<Batch>())) ?? []
        let completed = ReminderScheduler.completedSlotKeys(
            batches: batches, now: now, horizonDays: horizonDays)
        ReminderScheduler.reschedule(
            batches: batches, settings: settings, now: now,
            horizonDays: horizonDays, completedSlots: completed)
        LiveActivityController.refresh(
            batches: batches, now: now, graceMinutes: settings.graceMinutes,
            enabled: settings.remindersEnabled)
    }
}
```

- [ ] **Step 3: Add Info.plist keys via `project.yml`**

In `project.yml`, under `targets: > PillDaddy: > info: > properties:`, add two keys alongside the existing ones (`UILaunchScreen`, `UIBackgroundModes`, etc.):

```yaml
        NSSupportsLiveActivities: true
        CFBundleURLTypes:
          - CFBundleURLSchemes:
              - pilldaddy
```

- [ ] **Step 4: Regenerate and build**

Run `xcodegen generate`, then the build/test command. Expected: BUILD SUCCEEDS, tests PASS. (Verify `PillDaddy/Info.plist` now contains `NSSupportsLiveActivities` and `CFBundleURLTypes` after generation.)

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/AppRouter.swift PillDaddy/Services/ReminderSync.swift project.yml PillDaddy/Info.plist
git commit -m "feat: AppRouter, ReminderSync, Live Activity + URL scheme Info.plist keys"
```

---

## Task 11: App wiring — permission, delegate, scenePhase, deep links

Hook everything into the app lifecycle: request notification permission on first launch, handle taps, and re-sync on foreground.

**Files:**
- Modify: `PillDaddy/PillDaddyApp.swift`

- [ ] **Step 1: Rewrite `PillDaddyApp.swift`**

Replace the contents of `PillDaddy/PillDaddyApp.swift` with:

```swift
import SwiftUI
import SwiftData
import UserNotifications
import UIKit

/// Owns the notification delegate and the deep-link router (kept alive for the app's life).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let router = AppRouter()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }

    // Show banners while the app is foregrounded.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Tap → focus the batch on the Today tab.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let uuid = response.notification.request.content.userInfo["batchUUID"] as? String {
            await MainActor.run { router.pendingBatchUUID = uuid }
        }
    }
}

@main
struct PillDaddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer
    private let settings = ReminderSettings()

    init() {
        do {
            let config = ModelConfiguration(
                schema: PillDaddySchema.schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            container = try ModelContainer(for: PillDaddySchema.schema, configurations: config)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedTestData") {
            SeedData.seedIfEmpty(container.mainContext)
            try? container.mainContext.save()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appDelegate.router)
                .environment(settings)
                .onOpenURL { url in
                    if url.scheme == "pilldaddy", url.host == "batch" {
                        appDelegate.router.pendingBatchUUID = url.lastPathComponent
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { syncReminders() }
                }
        }
        .modelContainer(container)
    }

    @MainActor
    private func syncReminders() {
        let context = container.mainContext
        let batches = (try? context.fetch(FetchDescriptor<Batch>())) ?? []
        MissedReconciler.reconcile(
            batches: batches, now: .now, graceMinutes: settings.graceMinutes, in: context)
        ReminderSync.refresh(context: context, settings: settings)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: BUILD SUCCEEDS, tests PASS. (`MainTabView` doesn't yet read the new environment objects — that's Task 12; it compiles regardless.)

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/PillDaddyApp.swift
git commit -m "feat: app wiring for notifications, deep links, foreground sync"
```

---

## Task 12: Deep-link routing into Today

`MainTabView` switches to Today when a batch is focused; `TodayView` expands that batch and re-syncs after logging.

**Files:**
- Modify: `PillDaddy/Views/MainTabView.swift`
- Modify: `PillDaddy/Views/Today/TodayView.swift`

- [ ] **Step 1: Update `MainTabView`**

Replace the `body` and add the environment/selection state in `PillDaddy/Views/MainTabView.swift`. The new `struct MainTabView` body:

```swift
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }.tag(0)
            MedsView()
                .tabItem { Label("Meds", systemImage: "pills") }.tag(1)
            PlaceholderTab(title: "Reports", systemImage: "chart.bar")
                .tabItem { Label("Reports", systemImage: "chart.bar") }.tag(2)
            PlaceholderTab(title: "Health", systemImage: "heart")
                .tabItem { Label("Health", systemImage: "heart") }.tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }.tag(4)
        }
        .onChange(of: router.pendingBatchUUID) { _, uuid in
            if uuid != nil { selection = 0 }
        }
    }
}
```

(Leave the existing `PlaceholderTab` struct in the file; the `#Preview` will be updated in Task 13/Step note below.) Note the Settings tab now hosts `SettingsView` (created in Task 13) instead of a placeholder.

> If `SettingsView` does not yet exist when you compile this step, temporarily keep the Settings `PlaceholderTab` line and switch it to `SettingsView()` at the end of Task 13. To avoid a broken build, **do Task 13 before building Task 12**, or implement both before running the build/test command.

- [ ] **Step 2: Update the `MainTabView` preview**

The preview must supply the new environment object. Replace the `#Preview` in `MainTabView.swift`:

```swift
#Preview {
    MainTabView()
        .environment(AppRouter())
        .environment(ReminderSettings())
        .modelContainer(PreviewSupport.seededContainer())
}
```

- [ ] **Step 3: Wire focus handling into `TodayView`**

In `PillDaddy/Views/Today/TodayView.swift`, add the router environment after the existing `@Environment(\.modelContext)`:

```swift
    @Environment(AppRouter.self) private var router
    @Environment(ReminderSettings.self) private var settings
```

Then add these modifiers to the `NavigationStack` (alongside the existing `.onAppear`/`.onChange`):

```swift
            .onAppear { focusFromRouter() }
            .onChange(of: router.pendingBatchUUID) { _, _ in focusFromRouter() }
```

And update the existing state-change handler to also re-sync reminders. Replace:

```swift
            .onChange(of: batchDays.map { $0.state }) { _, _ in autoExpand() }
```

with:

```swift
            .onChange(of: batchDays.map { $0.state }) { _, _ in
                autoExpand()
                ReminderSync.refresh(context: context, settings: settings)
            }
```

Add these methods inside `TodayView`:

```swift
    /// Honor a deep link: jump to today and expand the requested batch.
    private func focusFromRouter() {
        guard let uuid = router.pendingBatchUUID else { return }
        if let batch = batches.first(where: { $0.uuid.uuidString == uuid }) {
            selectedDay = .now
            expandedID = batch.persistentModelID
        }
        router.pendingBatchUUID = nil
    }
```

- [ ] **Step 4: Update the `TodayView` preview**

Replace the `#Preview` in `TodayView.swift`:

```swift
#if DEBUG
#Preview {
    TodayView()
        .environment(AppRouter())
        .environment(ReminderSettings())
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 5: Build (after Task 13 exists) to verify it compiles**

Run the build/test command. Expected: BUILD SUCCEEDS, tests PASS, and the Today tab opens focused when launched from a deep link.

- [ ] **Step 6: Commit**

```bash
git add PillDaddy/Views/MainTabView.swift PillDaddy/Views/Today/TodayView.swift
git commit -m "feat: deep-link routing into Today + re-sync after logging"
```

---

## Task 13: `SettingsView`

Build the real Settings tab bound to `ReminderSettings`, re-syncing on every change, with a notification-permission status row.

**Files:**
- Create: `PillDaddy/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Write the implementation**

Create `PillDaddy/Views/Settings/SettingsView.swift`:

```swift
import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct SettingsView: View {
    @Environment(ReminderSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    private let graceChoices: [(String, Int)] = [
        ("30 min", 30), ("1 hour", 60), ("90 min", 90),
        ("2 hours", 120), ("3 hours", 180), ("4 hours", 240),
    ]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Reminders", isOn: $settings.remindersEnabled)
                } footer: {
                    Text("Schedules notifications and a Live Activity for each batch.")
                }

                Section("Timing") {
                    Toggle("15-minute heads-up", isOn: $settings.headsUpEnabled)
                    Picker("Grace window", selection: $settings.graceMinutes) {
                        ForEach(graceChoices, id: \.1) { Text($0.0).tag($0.1) }
                    }
                } footer: {
                    Text("How long after a batch's time before a dose is marked missed. "
                         + "Also how long reminders keep pestering.")
                }

                Section("Notifications") {
                    permissionRow
                }
            }
            .navigationTitle("Settings")
            .disabled(false)
            .onChange(of: settings.remindersEnabled) { _, _ in sync() }
            .onChange(of: settings.headsUpEnabled) { _, _ in sync() }
            .onChange(of: settings.graceMinutes) { _, _ in sync() }
            .task { await loadAuthStatus() }
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch authStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Notifications allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        default:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Notifications off — open Settings", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func sync() {
        ReminderSync.refresh(context: context, settings: settings)
    }

    private func loadAuthStatus() async {
        authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(ReminderSettings())
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: BUILD SUCCEEDS for app + widget; all tests PASS. (This is the point where Task 12's `SettingsView()` reference resolves.)

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Settings/SettingsView.swift
git commit -m "feat: SettingsView reminder controls + permission status"
```

---

## Task 14: Seed an overdue batch + full verification

Make the LA/missed paths dogfoodable from seed data, then run the whole verification pass.

**Files:**
- Modify: `PillDaddy/Helpers/SeedData.swift`
- Test: `PillDaddyTests/SeedDataTests.swift` (only if it asserts batch counts — see Step 2)

- [ ] **Step 1: Add an overdue batch to the seed**

In `PillDaddy/Helpers/SeedData.swift`, inside `seedIfEmpty`, add an early-morning batch that is already past a 2-hour grace by mid-day so the missed/LA paths exercise on launch. Add after the `green` batch insert (after line ~24):

```swift
        // An early batch (07:00) that is overdue by mid-morning so the missed/Live
        // Activity paths are exercisable from seed.
        let dawn = Batch(name: "Dawn", colorHex: "#8B5CF6",
                         timeOfDay: time(7, 0), mealRelation: .beforeFood, sortOrder: 2)
        context.insert(dawn)
```

Then add a med membership for it after the existing `BatchItem` inserts (after line ~34):

```swift
        context.insert(BatchItem(quantity: 1.0, medication: vitaminD, batch: dawn))
```

- [ ] **Step 2: Keep `SeedDataTests` green**

Run the build/test command. If `PillDaddyTests/SeedDataTests.swift` asserts an exact batch or batch-item count, update those expectations (now +1 batch "Dawn" and +1 BatchItem). If it only asserts non-empty / specific meds, no change is needed. Re-run until PASS.

- [ ] **Step 3: Full verification pass (per AGENTS.md)**

Run each and confirm:

```bash
xcodegen generate
xcodebuild -project PillDaddy.xcodeproj -scheme PillDaddy \
  -destination 'platform=iOS Simulator,name=iPhone 16' build test 2>&1 | tail -30
```

Expected: BUILD SUCCEEDS for `PillDaddy` and `PillDaddyWidgets`; **all** test suites PASS (`ReminderSettingsTests`, `ReminderTierTests`, `ReminderSchedulerTests`, `MissedReconcilerTests`, plus the pre-existing suites).

- [ ] **Step 4: Manual dogfood checklist (on a device for full fidelity; simulator covers most)**

Confirm by running the app (`-seedTestData` launch arg for seed):
- First launch shows the notification permission prompt.
- Settings tab: toggling Reminders, the heads-up switch, and the grace picker all work and persist across relaunch.
- With reminders on, scheduled notifications appear (set a batch `timeOfDay` near now via seed to observe heads-up/due/follow-up).
- The Live Activity appears for the overdue "Dawn" batch when the app is foregrounded, shows an advancing timer + progress bar, and escalates tier.
- Tapping a notification (or the Live Activity) opens the app on the Today tab with that batch expanded.
- Logging a batch ends its Live Activity and clears its pending follow-ups.
- Leaving "Dawn" unlogged past its grace window materializes `missed` rows (visible as missed status after relaunch).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Helpers/SeedData.swift PillDaddyTests/SeedDataTests.swift
git commit -m "feat: seed overdue batch; Session 3 verification"
```

---

## Self-review notes (coverage map)

- **Reminder lifecycle (−15 / 0 / +30/+60/+90 / stop):** Tasks 4–5 (`plan` emits heads-up/due/follow-ups, clipped to grace; apply layer schedules them).
- **Single global grace window driving pester + missed:** Task 2 (`graceMinutes`), used by Task 4 (follow-up clipping) and Task 6 (missed cutoff).
- **Missed materialization, idempotent, preserves taken/skipped, excludes discontinued, recurrence-aware:** Task 6.
- **Quick actions = none; tap opens app + deep-links to Today batch:** Tasks 10–12 (URL scheme, router, notification delegate, MainTabView/TodayView focus).
- **Settings v1 (master / grace / heads-up) + permission status:** Task 13; permission request on first launch: Task 11.
- **Local-only Live Activity, escalation via tier + timerInterval + progress bar, one at a time, gated by auth + master toggle:** Tasks 3, 7, 8, 9.
- **No push entitlement / signing preserved:** Task 8 widget target adds no entitlements; Task 10 adds only `NSSupportsLiveActivities` + URL scheme; CloudKit entitlements untouched.
- **Always runnable:** every task ends with a green build/test; the notification spine (Tasks 1–6) lands before the widget target (Tasks 7–8) and UI (11–13).
