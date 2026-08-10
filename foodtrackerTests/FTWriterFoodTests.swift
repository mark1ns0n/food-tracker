//
//  FTWriterFoodTests.swift
//  foodtrackerTests
//
//  F01.09 — an order, the meal out behind it, and the name they are both under.
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

    init() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = try SQLiteEventStore(
            databaseURL: directory.appendingPathComponent("CoreSync.sqlite"),
            deviceID: UUID()
        )
        context = try Fixture.makeContext()
        writer = FTWriter(
            modelContext: context,
            store: store,
            projector: FTProjector(eventLog: store, modelContext: context)
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

    func deliveries() throws -> [FoodEntry] {
        try context.fetch(FetchDescriptor<FoodEntry>()).sorted { $0.createdAt < $1.createdAt }
    }

    func dineIns() throws -> [DineInEntry] {
        try context.fetch(FetchDescriptor<DineInEntry>()).sorted { $0.createdAt < $1.createdAt }
    }

    func savedNames() throws -> [SavedName] {
        try context.fetch(FetchDescriptor<SavedName>()).sorted { $0.lastUsed < $1.lastUsed }
    }

    func events(_ entityType: String, _ entityID: UUID) throws -> [SyncEvent] {
        try store.projection(
            entityType: entityType,
            entityID: entityID,
            supportedSchemaVersion: FTEntity.schemaVersion
        ).events
    }

    func snapshot(_ context: ModelContext? = nil) throws -> [String] {
        let context = context ?? self.context
        func stamp(_ date: Date) -> String { String(format: "%.3f", date.timeIntervalSince1970) }

        var lines = try context.fetch(FetchDescriptor<FoodEntry>()).map {
            "delivery \($0.id) \($0.name) \($0.amount) \(stamp($0.createdAt))"
        }
        lines += try context.fetch(FetchDescriptor<DineInEntry>()).map {
            "dineIn \($0.id) \($0.name) \(stamp($0.createdAt))"
        }
        lines += try context.fetch(FetchDescriptor<SavedName>()).map {
            "savedName \($0.id) \($0.value) \(stamp($0.lastUsed))"
        }
        return lines.sorted()
    }
}

@MainActor
struct FTWriterFoodTests {
    private let thirtyOneDaysAgo = Date(timeIntervalSinceNow: -31 * 24 * 60 * 60)

    // MARK: Delivery

    @Test
    func addingADeliveryAlsoRemembersTheName() throws {
        let fixture = try Fixture()

        let id = try fixture.writer.addDelivery(name: "Talabat", amount: 4.5)

        #expect(try fixture.store.eventCount() == 2)
        #expect(try fixture.events(FTEntity.delivery, id).first?.operation == .create)
        let entry = try #require(try fixture.deliveries().first)
        #expect(entry.name == "Talabat")
        #expect(entry.amount == 4.5)

        let saved = try #require(try fixture.savedNames().first)
        #expect(saved.value == "Talabat")
        #expect(saved.id == FTIDs.savedName(value: "Talabat"))
    }

    // MARK: Dine-in and its cascade

    @Test
    func addingADineInWithANewNameWritesExactlyThreeEvents() throws {
        let fixture = try Fixture()

        let id = try fixture.writer.addDineIn(name: "Кафе")

        #expect(try fixture.store.eventCount() == 3)
        #expect(try fixture.events(FTEntity.dineIn, id).count == 1)

        #expect(try fixture.dineIns().map(\.name) == ["Кафе"])
        // The cascade: eating in blocks ordering from the same place, which is
        // what the zero-amount delivery entry expresses.
        let delivery = try #require(try fixture.deliveries().first)
        #expect(delivery.name == "Кафе")
        #expect(delivery.amount == 0)
        #expect(try fixture.savedNames().map(\.value) == ["Кафе"])
    }

    @Test
    func aRestaurantAlreadyInTheDeliveryListGetsNoSecondEntry() throws {
        let fixture = try Fixture()
        try fixture.writer.addDelivery(name: "Talabat", amount: 4.5)
        let before = try fixture.store.eventCount()

        try fixture.writer.addDineIn(name: "talabat")

        // Dine-in and the saved name's `lastUsed`, and no delivery: the entry
        // that would block ordering is already there.
        #expect(try fixture.store.eventCount() == before + 2)
        #expect(try fixture.deliveries().count == 1)
        #expect(try fixture.deliveries().first?.amount == 4.5)
    }

    @Test
    func anExpiredDeliveryDoesNotStandInForTheCascade() throws {
        // Expiry hides a row rather than deleting it (decision 1), so the
        // cascade has to ask whether the entry is still *active* — an order from
        // two months ago blocks nothing.
        let fixture = try Fixture()
        try fixture.writer.addDelivery(name: "Talabat", amount: 4.5, createdAt: thirtyOneDaysAgo)
        let before = try fixture.store.eventCount()

        try fixture.writer.addDineIn(name: "Talabat")

        #expect(try fixture.store.eventCount() == before + 3)
        #expect(try fixture.deliveries().filter { !$0.isExpired }.map(\.amount) == [0])
    }

    // MARK: Saved names

    @Test
    func theSameNameInAnotherCaseUpdatesTheOneEntityInsteadOfMakingASecond() throws {
        let fixture = try Fixture()
        let entityID = FTIDs.savedName(value: "Talabat")

        try fixture.writer.upsertSavedName(value: "Talabat", lastUsed: thirtyOneDaysAgo)
        try fixture.writer.upsertSavedName(value: "talabat")

        let events = try fixture.events(FTEntity.savedName, entityID)
        #expect(events.count == 2)
        #expect(events.first?.operation == .create)
        #expect(events.last?.operation == .update)

        let saved = try fixture.savedNames()
        #expect(saved.count == 1)
        // Only `lastUsed` travelled, so the suggestion keeps the spelling it was
        // first typed in.
        #expect(saved.first?.value == "Talabat")
        #expect(saved.first?.lastUsed ?? .distantPast > thirtyOneDaysAgo)
    }

    @Test
    func aNameReusedByAnOrderIsRefreshedRatherThanRecreated() throws {
        let fixture = try Fixture()
        try fixture.writer.upsertSavedName(value: "Talabat", lastUsed: thirtyOneDaysAgo)

        try fixture.writer.addDelivery(name: "Talabat", amount: 2)

        let events = try fixture.events(FTEntity.savedName, FTIDs.savedName(value: "Talabat"))
        #expect(events.map(\.operation) == [.create, .update])
        #expect(try fixture.savedNames().count == 1)
    }

    // MARK: The writer and the projector agree

    @Test
    func theTablesMatchAFullReplayOfEverythingTheWriterWrote() throws {
        let fixture = try Fixture()
        try fixture.writer.addDelivery(name: "Talabat", amount: 4.5)
        try fixture.writer.addDelivery(name: "Talabat mart", amount: 12)
        try fixture.writer.addDineIn(name: "Кафе")
        try fixture.writer.addDineIn(name: "talabat")
        try fixture.writer.upsertSavedName(value: "Sushi")

        let replayed = try Fixture.makeContext()
        try FTProjector(eventLog: fixture.store, modelContext: replayed).replayAll()

        #expect(try fixture.snapshot() == (try fixture.snapshot(replayed)))
        #expect(try fixture.deliveries().count == 3)
        #expect(try fixture.savedNames().count == 4)
    }
}
