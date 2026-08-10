//
//  FTWriterGroceryTests.swift
//  foodtrackerTests
//
//  F01.08 — the writer and the projector are the same code path.
//

import CoreSync
import Foundation
import SwiftData
import Testing

@testable import foodtracker

/// A writer over a real store, because the store is what stamps the HLC — the
/// ordering these events will be read back in is not something a fixture could
/// stand in for here.
@MainActor
private struct Fixture {
    let store: SQLiteEventStore
    let context: ModelContext
    let projector: FTProjector
    let writer: FTWriter

    init() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = try SQLiteEventStore(
            databaseURL: directory.appendingPathComponent("CoreSync.sqlite"),
            deviceID: UUID()
        )
        context = try Fixture.makeContext()
        projector = FTProjector(eventLog: store, modelContext: context)
        writer = FTWriter(modelContext: context, store: store, projector: projector)
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

    func groceries() throws -> [Item] {
        try context.fetch(FetchDescriptor<Item>()).sorted { $0.createdAt < $1.createdAt }
    }

    func events(_ entityID: UUID) throws -> [SyncEvent] {
        try store.projection(
            entityType: FTEntity.grocery,
            entityID: entityID,
            supportedSchemaVersion: FTEntity.schemaVersion
        ).events
    }

    /// What the six tables hold, flattened — the comparison a replay has to
    /// reproduce.
    func snapshot(_ context: ModelContext? = nil) throws -> [String] {
        let context = context ?? self.context
        return try context.fetch(FetchDescriptor<Item>()).map {
            "grocery \($0.id) \($0.name) \($0.status.rawValue) \($0.groceryType.rawValue) "
                + String(format: "%.3f", $0.createdAt.timeIntervalSince1970)
        }.sorted()
    }
}

@MainActor
struct FTWriterGroceryTests {
    // MARK: One action, one event

    @Test
    func addingAGroceryWritesOneCreateAndNothingElse() throws {
        let fixture = try Fixture()

        let id = try fixture.writer.addGrocery(name: "Рис", type: .side)

        let events = try fixture.events(id)
        #expect(events.count == 1)
        #expect(events.first?.operation == .create)

        let rows = try fixture.groceries()
        #expect(rows.count == 1)
        #expect(rows.first?.id == id)
        #expect(rows.first?.name == "Рис")
        #expect(rows.first?.groceryType == .side)
        #expect(rows.first?.status == .available)
    }

    @Test
    func aToggleWritesExactlyOneStatusUpdate() throws {
        let fixture = try Fixture()
        let id = try fixture.writer.addGrocery(name: "Рис", type: .side)

        try fixture.writer.toggleGrocery(id: id)

        let events = try fixture.events(id)
        #expect(events.count == 2)
        let update = try #require(events.last)
        #expect(update.operation == .update)
        // Only the status: an update that also carried the name would overwrite
        // a rename that reached the log from the other device in between.
        #expect(update.payload == .object(["status": .string("used")]))
        #expect(try fixture.groceries().first?.status == .used)
    }

    @Test
    func aToggleBackIsAnotherUpdateRatherThanAnUndo() throws {
        let fixture = try Fixture()
        let id = try fixture.writer.addGrocery(name: "Рис", type: .side)

        try fixture.writer.toggleGrocery(id: id)
        try fixture.writer.toggleGrocery(id: id)

        #expect(try fixture.events(id).count == 3)
        #expect(try fixture.groceries().first?.status == .available)
    }

    @Test
    func anEditCarriesTheNameAndTheTypeAndLeavesTheStatusAlone() throws {
        let fixture = try Fixture()
        let id = try fixture.writer.addGrocery(name: "Рис", type: .side)
        try fixture.writer.toggleGrocery(id: id)

        try fixture.writer.editGrocery(id: id, name: "Гречка", type: .main)

        let update = try #require(try fixture.events(id).last)
        #expect(update.payload == .object([
            "name": .string("Гречка"),
            "type": .string("main"),
        ]))
        let row = try #require(try fixture.groceries().first)
        #expect(row.name == "Гречка")
        #expect(row.groceryType == .main)
        #expect(row.status == .used)
    }

    @Test
    func resettingThreeGroceriesWritesExactlyThreeEvents() throws {
        let fixture = try Fixture()
        let ids = try (0..<3).map { try fixture.writer.addGrocery(name: "Товар \($0)", type: .main) }
        for id in ids {
            try fixture.writer.toggleGrocery(id: id)
        }

        try fixture.writer.resetGroceries(ids: ids)

        let reset = try ids.flatMap { try fixture.events($0) }
            .filter { $0.payload == .object(["status": .string("available")]) }
        #expect(reset.count == 3)
        #expect(try fixture.groceries().allSatisfy { $0.status == .available })
    }

    @Test
    func aDeleteLeavesNoRowAndATombstoneInTheLog() throws {
        let fixture = try Fixture()
        let id = try fixture.writer.addGrocery(name: "Рис", type: .side)

        try fixture.writer.deleteGrocery(id: id)

        #expect(try fixture.groceries().isEmpty)
        #expect(try fixture.events(id).last?.operation == .delete)
    }

    // MARK: The writer and the projector agree

    @Test
    func theTablesMatchAFullReplayOfEverythingTheWriterWrote() throws {
        // The point of routing writes through the log: whatever sequence of
        // actions the user takes, the rows on screen are the rows a device that
        // has only ever seen the events would build.
        let fixture = try Fixture()
        let rice = try fixture.writer.addGrocery(name: "Рис", type: .side)
        let salad = try fixture.writer.addGrocery(name: "Салат", type: .salad)
        let bread = try fixture.writer.addGrocery(name: "Хлеб", type: .main)
        try fixture.writer.toggleGrocery(id: rice)
        try fixture.writer.editGrocery(id: salad, name: "Огурцы", type: .salad)
        try fixture.writer.toggleGrocery(id: salad)
        try fixture.writer.deleteGrocery(id: bread)
        try fixture.writer.resetGroceries(ids: [rice, salad])

        let replayed = try Fixture.makeContext()
        try FTProjector(eventLog: fixture.store, modelContext: replayed).replayAll()

        #expect(try fixture.snapshot() == (try fixture.snapshot(replayed)))
        #expect(try fixture.snapshot().count == 2)
    }

    // MARK: Rows that predate the log

    @Test
    func aRowTheLogHasNeverHeardOfIsWrittenIntoItBeforeItChanges() throws {
        // Between here and the backfill of F01.11 the store is full of rows no
        // event accounts for. An update alone would project to nothing and the
        // projector would take the row away, so the first mutation records what
        // the row already held.
        let fixture = try Fixture()
        let legacy = Item(name: "Рис", status: .available, type: .side)
        fixture.context.insert(legacy)
        try fixture.context.save()

        try fixture.writer.toggleGrocery(id: legacy.id)

        let events = try fixture.events(legacy.id)
        #expect(events.count == 2)
        #expect(events.first?.operation == .create)
        #expect(events.first?.payload == .object([
            "name": .string("Рис"),
            "status": .string("available"),
            "type": .string("side"),
            "createdAt": .string(FTDate.string(legacy.createdAt)),
        ]))

        let rows = try fixture.groceries()
        #expect(rows.count == 1)
        #expect(rows.first?.name == "Рис")
        #expect(rows.first?.status == .used)
    }

    @Test
    func aGroceryNeitherTheLogNorTheTableHasIsRefused() throws {
        let fixture = try Fixture()
        let missing = UUID()

        #expect(throws: FTWriterError.unknownGrocery(missing)) {
            try fixture.writer.toggleGrocery(id: missing)
        }
    }

    @Test
    func aGroceryTheLogSaysWasDeletedIsNotResurrectedByAnEdit() throws {
        // The row is gone but its slice is not: turning a late edit into a
        // `create` would bring back a grocery the user threw away.
        let fixture = try Fixture()
        let id = try fixture.writer.addGrocery(name: "Рис", type: .side)
        try fixture.writer.deleteGrocery(id: id)

        #expect(throws: FTWriterError.deletedGrocery(id)) {
            try fixture.writer.editGrocery(id: id, name: "Гречка", type: .main)
        }
    }
}
