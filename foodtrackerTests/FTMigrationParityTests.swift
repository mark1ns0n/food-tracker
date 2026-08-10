//
//  FTMigrationParityTests.swift
//  foodtrackerTests
//
//  F01.12 — the acceptance of phases 1–2: what the user saw before the
//  migration is what the log replays after it.
//

import CoreSync
import Foundation
import SwiftData
import Testing

@testable import foodtracker

/// A store with a little of everything the old app could hold, and a snapshot
/// of what the user *sees* — not the rows, but the projections the views
/// compute from them: the grocery lists per type, the active delivery list and
/// its total, the suggestion order, the schedule fields, the debt total.
///
/// Row-level parity is F01.11's test; this one closes the loop one level up,
/// where a migration bug would actually be noticed.
@MainActor
private struct Fixture {
    let store: SQLiteEventStore
    let context: ModelContext
    let service: FTBackfillService

    /// Whole seconds, so every date survives the ISO-8601 trip through the
    /// payload codecs exactly. Relative to the real clock because expiry is
    /// (deliberately, decision 1) a projection off `Date()`.
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())

    init() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = try SQLiteEventStore(
            databaseURL: directory.appendingPathComponent("CoreSync.sqlite"),
            deviceID: UUID()
        )
        context = try Fixture.makeContext()
        service = FTBackfillService(
            modelContext: context,
            store: store,
            projector: FTProjector(eventLog: store, modelContext: context),
            defaults: UserDefaults(suiteName: "FTMigrationParityTests." + UUID().uuidString)!
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

    /// The fixture from the card: six groceries across every type and status,
    /// three deliveries with one already expired, two dine-ins, three saved
    /// names, a schedule with a fast running, two debts. Seventeen rows.
    func seedLegacyStore() throws {
        let groceries: [(String, ItemStatus, GroceryType)] = [
            ("Bread", .available, .main),
            ("Chicken", .used, .main),
            ("Rice", .available, .side),
            ("Pasta", .used, .side),
            ("Lettuce", .available, .salad),
            ("Cucumber", .used, .salad),
        ]
        for (offset, grocery) in groceries.enumerated() {
            let item = Item(name: grocery.0, status: grocery.1, type: grocery.2)
            item.createdAt = now.addingTimeInterval(TimeInterval(-3_600 + offset * 60))
            context.insert(item)
        }

        context.insert(FoodEntry(name: "Talabat", amount: 12.5, createdAt: now.addingTimeInterval(-3_600)))
        context.insert(FoodEntry(name: "Jahez", amount: 4, createdAt: now.addingTimeInterval(-7_200)))
        context.insert(FoodEntry(name: "Old Place", amount: 3, createdAt: now.addingTimeInterval(-31 * 86_400)))

        context.insert(DineInEntry(name: "Cafe", createdAt: now.addingTimeInterval(-10_800)))
        context.insert(DineInEntry(name: "Diner", createdAt: now.addingTimeInterval(-14_400)))

        context.insert(SavedName(value: "Talabat", lastUsed: now.addingTimeInterval(-3_600)))
        context.insert(SavedName(value: "Jahez", lastUsed: now.addingTimeInterval(-7_200)))
        context.insert(SavedName(value: "Cafe", lastUsed: now.addingTimeInterval(-10_800)))

        let schedule = FastingEntry(startHour: 20, startMinute: 0, durationMinutes: 960)
        schedule.activeStartDate = now.addingTimeInterval(-7_200)
        context.insert(schedule)

        context.insert(FastingDebt(missedMinutes: 30, createdAt: now.addingTimeInterval(-86_400)))
        context.insert(FastingDebt(missedMinutes: 45, createdAt: now.addingTimeInterval(-3_600)))

        try context.save()
    }

    /// What the tabs show, computed the way the views compute it: the same
    /// filters, the same `@Query` sort orders, the same summary strings.
    ///
    /// The schedule's `createdAt` is deliberately absent: after a replay it is
    /// legitimately the backfill event's timestamp (F01.07 — the payload has no
    /// date of its own), and no view reads it.
    func observableSnapshot(_ context: ModelContext? = nil) throws -> [String] {
        let context = context ?? self.context
        func stamp(_ date: Date?) -> String {
            date.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? "-"
        }

        var lines: [String] = []

        let items = try context.fetch(
            FetchDescriptor<Item>(sortBy: [SortDescriptor(\.createdAt)])
        )
        for type in GroceryType.allCases {
            let ofType = items.filter { $0.groceryType == type }
            let available = ofType.filter { $0.status == .available }.map(\.name)
            let used = ofType.filter { $0.status == .used }.map(\.name)
            lines.append("groceries \(type.rawValue) available: " + available.joined(separator: ", "))
            lines.append("groceries \(type.rawValue) used: " + used.joined(separator: ", "))
        }

        let activeDeliveries = try context.fetch(
            FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        ).filter { !$0.isExpired }
        lines += activeDeliveries.map {
            "delivery \($0.name) \(String(format: "%.1f", $0.amount)) \(stamp($0.createdAt))"
        }
        let total = activeDeliveries.reduce(0) { $0 + $1.amount }
        lines.append("delivery summary (\(activeDeliveries.count)) \(String(format: "%.1f", total)) KD")

        let activeDineIns = try context.fetch(
            FetchDescriptor<DineInEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        ).filter { !$0.isExpired }
        lines += activeDineIns.map { "dineIn \($0.name) \(stamp($0.createdAt))" }
        lines.append("dineIn summary (\(activeDineIns.count))")

        lines += try context.fetch(
            FetchDescriptor<SavedName>(sortBy: [SortDescriptor(\.lastUsed, order: .reverse)])
        ).map { "suggestion \($0.value) \(stamp($0.lastUsed))" }

        if let schedule = try context.fetch(FetchDescriptor<FastingEntry>()).first {
            lines.append(
                "schedule \(schedule.formattedStartTime) \(schedule.formattedDuration)"
                    + " fasting=\(schedule.isFasting) since=\(stamp(schedule.activeStartDate))"
            )
        }

        let debts = try context.fetch(
            FetchDescriptor<FastingDebt>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )
        lines += debts.map { "debt \($0.formattedDebt) \(stamp($0.createdAt))" }
        lines.append("debt total \(debts.reduce(0) { $0 + $1.missedMinutes })m")

        return lines
    }

    func wipeProjectedTables() throws {
        func wipe<Model: PersistentModel>(_ type: Model.Type) throws {
            for row in try context.fetch(FetchDescriptor<Model>()) {
                context.delete(row)
            }
        }
        try wipe(Item.self)
        try wipe(FoodEntry.self)
        try wipe(DineInEntry.self)
        try wipe(SavedName.self)
        try wipe(FastingEntry.self)
        try wipe(FastingDebt.self)
        try context.save()
    }
}

@MainActor
struct FTMigrationParityTests {
    @Test
    func theLogAloneRebuildsEverythingTheUserWasLookingAt() throws {
        let fixture = try Fixture()
        try fixture.seedLegacyStore()
        let before = try fixture.observableSnapshot()

        try fixture.service.runIfNeeded()

        // Seventeen rows, seventeen creates — and then the tables are emptied
        // on purpose before the second replay: `runIfNeeded` already replayed
        // once, and without the wipe a projector that quietly kept old rows
        // around would pass this test on leftovers.
        #expect(try fixture.store.eventCount() == 17)
        try fixture.wipeProjectedTables()
        try FTProjector(eventLog: fixture.store, modelContext: fixture.context).replayAll()

        #expect(try fixture.observableSnapshot() == before)
    }

    @Test
    func aDeviceThatHasOnlyTheLogSeesTheSameTabs() throws {
        // The same comparison into a context that has never held the legacy
        // rows — the shape of super-app's first pull (F01.17).
        let fixture = try Fixture()
        try fixture.seedLegacyStore()
        let before = try fixture.observableSnapshot()

        try fixture.service.runIfNeeded()

        let fresh = try Fixture.makeContext()
        try FTProjector(eventLog: fixture.store, modelContext: fresh).replayAll()

        #expect(try fixture.observableSnapshot(fresh) == before)
    }
}
