//
//  FTBackfillTests.swift
//  foodtrackerTests
//
//  F01.11 — the rows that predate the log are written into it, once.
//

import CoreSync
import Foundation
import SwiftData
import Testing

@testable import foodtracker

@MainActor
private struct Fixture {
    let store: SQLiteEventStore
    let context: ModelContext
    let writer: FTWriter
    let service: FTBackfillService
    let defaults: UserDefaults

    init() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = try SQLiteEventStore(
            databaseURL: directory.appendingPathComponent("CoreSync.sqlite"),
            deviceID: UUID()
        )
        context = try Fixture.makeContext()
        let projector = FTProjector(eventLog: store, modelContext: context)
        writer = FTWriter(modelContext: context, store: store, projector: projector)
        defaults = UserDefaults(suiteName: "FTBackfillTests." + UUID().uuidString)!
        service = FTBackfillService(
            modelContext: context,
            store: store,
            projector: projector,
            defaults: defaults
        )
    }

    static func makeContext() throws -> ModelContext {
        let schema = Schema([
            Item.self,
            FoodEntry.self,
            SavedName.self,
            DineInEntry.self,
            FastingEntry.self,
            FastingDebt.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// The store as it stood before the log existed: rows everywhere, and not
    /// one event about any of them. Ten rows — one of the delivery entries
    /// already expired, the fast running.
    func seedLegacyStore(at noon: Date) throws {
        context.insert(Item(name: "Rice", status: .available, type: .side))
        context.insert(Item(name: "Chicken", status: .used, type: .main))
        context.insert(FoodEntry(name: "Talabat", amount: 12.5, createdAt: noon))
        context.insert(
            FoodEntry(name: "Old Place", amount: 3, createdAt: noon.addingTimeInterval(-31 * 86_400))
        )
        context.insert(DineInEntry(name: "Cafe", createdAt: noon))
        context.insert(SavedName(value: "Talabat", lastUsed: noon))
        context.insert(SavedName(value: "Cafe", lastUsed: noon))
        let schedule = FastingEntry(startHour: 20, startMinute: 0, durationMinutes: 960)
        schedule.activeStartDate = noon
        context.insert(schedule)
        context.insert(FastingDebt(missedMinutes: 30, createdAt: noon))
        context.insert(FastingDebt(missedMinutes: 45, createdAt: noon.addingTimeInterval(60)))
        try context.save()
    }

    /// The observable state, without row ids: the replay legitimately rewrites
    /// the ids of the saved-name and schedule rows (their entities are not keyed
    /// by row id), and what has to survive the migration is what the user sees.
    func snapshot(_ context: ModelContext? = nil) throws -> [String] {
        let context = context ?? self.context
        func stamp(_ date: Date?) -> String {
            date.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? "-"
        }

        var lines = try context.fetch(FetchDescriptor<Item>()).map {
            "grocery \($0.name) \($0.status.rawValue) \($0.groceryType.rawValue) \(stamp($0.createdAt))"
        }
        lines += try context.fetch(FetchDescriptor<FoodEntry>()).map {
            "delivery \($0.name) \($0.amount) \(stamp($0.createdAt))"
        }
        lines += try context.fetch(FetchDescriptor<DineInEntry>()).map {
            "dineIn \($0.name) \(stamp($0.createdAt))"
        }
        lines += try context.fetch(FetchDescriptor<SavedName>()).map {
            "savedName \($0.value) \(stamp($0.lastUsed))"
        }
        lines += try context.fetch(FetchDescriptor<FastingEntry>()).map {
            "schedule \($0.startHour):\($0.startMinute) \($0.durationMinutes) \(stamp($0.activeStartDate))"
        }
        lines += try context.fetch(FetchDescriptor<FastingDebt>()).map {
            "debt \($0.missedMinutes) \(stamp($0.createdAt))"
        }
        return lines.sorted()
    }
}

@MainActor
struct FTBackfillTests {
    private let noon = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: The migration itself

    @Test
    func everyRowBecomesOneCreateAndTheReplayChangesNothingTheUserSees() throws {
        let fixture = try Fixture()
        try fixture.seedLegacyStore(at: noon)
        let before = try fixture.snapshot()

        try fixture.service.runIfNeeded()

        // Ten rows, ten creates — and the tables the replay rebuilt from those
        // events hold exactly what the legacy rows held.
        #expect(try fixture.store.eventCount() == 10)
        #expect(try fixture.snapshot() == before)
        #expect(fixture.service.isDone)
    }

    @Test
    func aFreshContextReplaysTheBackfilledLogIntoTheSameState() throws {
        let fixture = try Fixture()
        try fixture.seedLegacyStore(at: noon)

        try fixture.service.runIfNeeded()

        let replayed = try Fixture.makeContext()
        try FTProjector(eventLog: fixture.store, modelContext: replayed).replayAll()
        #expect(try fixture.snapshot(replayed) == (try fixture.snapshot()))
    }

    @Test
    func expiredEntriesMigrateAsTheyAre() throws {
        // Expiry is a projection (decision 1), not a fact about the data: the
        // row travels, and every device hides it the same way.
        let fixture = try Fixture()
        try fixture.seedLegacyStore(at: noon)

        try fixture.service.runIfNeeded()

        let deliveries = try fixture.context.fetch(FetchDescriptor<FoodEntry>())
        #expect(deliveries.count == 2)
        #expect(deliveries.contains { $0.name == "Old Place" && $0.isExpired })
    }

    // MARK: One shot, twice over

    @Test
    func theFlagStopsASecondRunBeforeItTouchesTheStore() throws {
        let fixture = try Fixture()
        try fixture.seedLegacyStore(at: noon)
        try fixture.service.runIfNeeded()
        let count = try fixture.store.eventCount()

        // A row that appears after the backfill (it should not, but the flag is
        // the guard that makes "should not" cheap): with the flag up, a second
        // run must not even look at it — and must not replay, which would drop
        // a row the log cannot account for.
        fixture.context.insert(Item(name: "Late", status: .available, type: .salad))
        try fixture.context.save()

        try fixture.service.runIfNeeded()

        #expect(try fixture.store.eventCount() == count)
        #expect(try fixture.context.fetch(FetchDescriptor<Item>()).contains { $0.name == "Late" })
    }

    @Test
    func withTheFlagClearedTheDeterministicIdsMakeTheRerunANoOp() throws {
        let fixture = try Fixture()
        try fixture.seedLegacyStore(at: noon)
        try fixture.service.runIfNeeded()
        let count = try fixture.store.eventCount()

        fixture.defaults.removeObject(forKey: FTBackfillService.doneKey)
        try fixture.service.runIfNeeded()

        // The second run re-appends the same drafts; the store recognizes every
        // event id and content pair and inserts nothing.
        #expect(try fixture.store.eventCount() == count)
        #expect(fixture.service.isDone)
    }

    // MARK: Saved names — the entity is the value, not the row

    @Test
    func spellingsOfOneNameCollapseIntoOneEntityAndTheLatestSpellingWins() throws {
        let fixture = try Fixture()
        fixture.context.insert(SavedName(value: "Talabat", lastUsed: noon))
        fixture.context.insert(
            SavedName(value: "talabat", lastUsed: noon.addingTimeInterval(3_600))
        )
        try fixture.context.save()

        try fixture.service.runIfNeeded()

        // One entity, one event, one row — under the deterministic id, which is
        // what lets a second device upsert the same name instead of doubling it.
        #expect(try fixture.store.eventCount() == 1)
        let rows = try fixture.context.fetch(FetchDescriptor<SavedName>())
        #expect(rows.count == 1)
        #expect(rows.first?.value == "talabat")
        #expect(rows.first?.id == FTIDs.savedName(value: "Talabat"))
    }

    @Test
    func theReplayRemovesTheLegacyRowTheBackfilledEntityWouldOtherwiseSitBeside() throws {
        // The requirement recorded in F01.09: a legacy row has a random id, the
        // entity a derived one, so without the closing replay the suggestion
        // list would show the same name twice.
        let fixture = try Fixture()
        let legacy = SavedName(value: "Talabat", lastUsed: noon)
        fixture.context.insert(legacy)
        try fixture.context.save()
        let legacyID = legacy.id

        try fixture.service.runIfNeeded()

        let rows = try fixture.context.fetch(FetchDescriptor<SavedName>())
        #expect(rows.count == 1)
        #expect(rows.first?.id == FTIDs.savedName(value: "Talabat"))
        #expect(rows.first?.id != legacyID)
    }

    // MARK: The schedule — a singleton with a per-device event

    @Test
    func theScheduleKeepsItsRunningFastAndTakesTheSingletonIdentity() throws {
        let fixture = try Fixture()
        let schedule = FastingEntry(startHour: 21, startMinute: 30, durationMinutes: 900)
        schedule.activeStartDate = noon
        fixture.context.insert(schedule)
        try fixture.context.save()

        try fixture.service.runIfNeeded()

        let rows = try fixture.context.fetch(FetchDescriptor<FastingEntry>())
        #expect(rows.count == 1)
        #expect(rows.first?.id == FTIDs.fastingSchedule())
        #expect(rows.first?.activeStartDate == noon)

        // Per-device on purpose (the U01 pattern): the second device's backfill
        // is its own event, and LWW resolves the two schedules.
        let events = try fixture.store.projection(
            entityType: FTEntity.fastingSchedule,
            entityID: FTIDs.fastingSchedule(),
            supportedSchemaVersion: FTEntity.schemaVersion
        ).events
        #expect(
            events.map(\.id) == [
                FTIDs.backfillEventID(deviceID: fixture.store.deviceID, name: "ft.fasting.schedule")
            ]
        )
    }

    // MARK: Rows the writer already materialized

    @Test
    func aGroceryTheWriterAlreadyWroteDownTakesTheBackfillCreateWithoutChanging() throws {
        // Between F01.08 and this task, the first toggle of a legacy grocery
        // writes it into the log (`inLog`) under a store-minted event id. The
        // backfill's create is a different event on the same entity, carrying
        // the same content the fold already holds — nothing conflicts, nothing
        // moves.
        let fixture = try Fixture()
        let item = Item(name: "Rice", status: .available, type: .side)
        fixture.context.insert(item)
        try fixture.context.save()
        try fixture.writer.toggleGrocery(id: item.id)

        try fixture.service.runIfNeeded()

        // Materialized create + toggle update + backfill create.
        #expect(try fixture.store.eventCount() == 3)
        let rows = try fixture.context.fetch(FetchDescriptor<Item>())
        #expect(rows.count == 1)
        #expect(rows.first?.status == .used)
    }

    @Test
    func aGroceryTheUserDeletedStaysDeleted() throws {
        // The backfill walks the rows, and a deleted grocery has none — its
        // slice in the log (create + tombstone) is the only trace, and the
        // closing replay honors it.
        let fixture = try Fixture()
        let item = Item(name: "Rice", status: .available, type: .side)
        fixture.context.insert(item)
        try fixture.context.save()
        try fixture.writer.deleteGrocery(id: item.id)
        let count = try fixture.store.eventCount()

        try fixture.service.runIfNeeded()

        #expect(try fixture.store.eventCount() == count)
        #expect(try fixture.context.fetch(FetchDescriptor<Item>()).isEmpty)
    }

    // MARK: Nothing to migrate

    @Test
    func anEmptyStoreBackfillsToAnEmptyLogAndStillSetsTheFlag() throws {
        let fixture = try Fixture()

        try fixture.service.runIfNeeded()

        #expect(try fixture.store.eventCount() == 0)
        #expect(fixture.service.isDone)
    }

    // MARK: Rows the lightweight migration handed the same id

    /// Every test above builds its rows by calling the model initializers, and
    /// each call draws its own `UUID()` — which is the one shape the real
    /// upgrade never produces. SwiftData evaluates the `id: UUID = UUID()`
    /// default **once** when it adds the column, so a store carried over from
    /// before F01.02 arrives with one id per *table*. That is what the owner's
    /// phone did on 2026-08-11, and it took the backfill down.
    private func seedStoreAsTheMigrationLeavesIt(_ fixture: Fixture) throws {
        let groceryID = UUID()
        for name in ["Rice", "Chicken", "Salad"] {
            let row = Item(name: name, status: .available, type: .side)
            row.id = groceryID
            fixture.context.insert(row)
        }
        let deliveryID = UUID()
        for name in ["Talabat", "Deliveroo"] {
            let row = FoodEntry(name: name, amount: 10, createdAt: noon)
            row.id = deliveryID
            fixture.context.insert(row)
        }
        try fixture.context.save()
    }

    /// The regression: without the repair this throws `eventIDConflict`, and if
    /// the conflict were merely dodged the replay would keep one grocery and
    /// delete the other two.
    @Test
    func rowsTheMigrationGaveOneSharedIDStillBecomeOneEntityEach() throws {
        let fixture = try Fixture()
        try seedStoreAsTheMigrationLeavesIt(fixture)
        let before = try fixture.snapshot()

        try fixture.service.runIfNeeded()

        #expect(try fixture.store.eventCount() == 5)
        #expect(try fixture.snapshot() == before)

        let groceries = try fixture.context.fetch(FetchDescriptor<Item>())
        #expect(groceries.count == 3)
        #expect(Set(groceries.map(\.id)).count == 3)
    }

    /// The repair must not reach across tables either: `backfillEventID` hashes
    /// the entity id alone, so a grocery and a delivery holding the same
    /// migration default would produce the same event id.
    @Test
    func aGroceryAndADeliveryHandedTheSameIDDoNotShareAnEventID() throws {
        let fixture = try Fixture()
        let shared = UUID()
        let grocery = Item(name: "Rice", status: .available, type: .side)
        grocery.id = shared
        fixture.context.insert(grocery)
        let delivery = FoodEntry(name: "Talabat", amount: 10, createdAt: noon)
        delivery.id = shared
        fixture.context.insert(delivery)
        try fixture.context.save()

        try fixture.service.runIfNeeded()

        #expect(try fixture.store.eventCount() == 2)
        #expect(grocery.id != delivery.id)
    }

    @Test
    func asecondRunLeavesTheRepairedIdentitiesWhereTheyAre() throws {
        let fixture = try Fixture()
        try seedStoreAsTheMigrationLeavesIt(fixture)
        try fixture.service.runIfNeeded()
        let ids = try fixture.context.fetch(FetchDescriptor<Item>()).map(\.id).sorted {
            $0.uuidString < $1.uuidString
        }

        try fixture.service.runIfNeeded()

        let after = try fixture.context.fetch(FetchDescriptor<Item>()).map(\.id).sorted {
            $0.uuidString < $1.uuidString
        }
        #expect(after == ids)
    }

    /// Once the log names row ids, reassigning them would orphan the events and
    /// let the replay delete the rows they describe. Refusing is the outcome to
    /// want, so the duplicates must survive untouched and the append must fail.
    @Test
    func aLogThatAlreadyHasEventsIsRefusedRatherThanReidentified() throws {
        let fixture = try Fixture()
        _ = try fixture.writer.addGrocery(name: "Written first", type: .main)
        #expect(try fixture.store.eventCount() == 1)

        let shared = UUID()
        let rows = ["Rice", "Chicken"].map { name -> Item in
            let row = Item(name: name, status: .available, type: .side)
            row.id = shared
            fixture.context.insert(row)
            return row
        }
        try fixture.context.save()

        #expect(throws: (any Error).self) {
            try fixture.service.runIfNeeded()
        }
        #expect(rows.allSatisfy { $0.id == shared })
        #expect(!fixture.service.isDone)
    }
}
