//
//  ModelIdentityTests.swift
//  foodtrackerTests
//
//  F01.02 — every model carries a stable `id: UUID`.
//

import Foundation
import SwiftData
import Testing

@testable import foodtracker

/// The identity `ft.*` events will be keyed by (F01.06).
///
/// Until F01.02 the models had no identity of their own — only SwiftData's
/// `persistentModelID`, which is local to one store and cannot name the same
/// row on another device. These tests pin the two properties the sync layer
/// depends on: an id exists and differs per row, and it survives a round trip
/// through the store unchanged.
@MainActor
struct ModelIdentityTests {
    private func makeContext() throws -> ModelContext {
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

    @Test
    func freshRowsOfTheSameTypeGetDifferentIDs() throws {
        let context = try makeContext()

        let rice = Item(name: "Рис")
        let buckwheat = Item(name: "Гречка")
        context.insert(rice)
        context.insert(buckwheat)
        try context.save()

        #expect(rice.id != buckwheat.id)
    }

    @Test
    func idSurvivesTheRoundTripThroughTheStore() throws {
        let context = try makeContext()

        let entry = FoodEntry(name: "Суши", amount: 1200)
        let expected = entry.id
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == expected)
    }

    @Test
    func everyModelAcceptsACallerSuppliedID() throws {
        let context = try makeContext()

        // The backfill (F01.11) reconstructs rows from the log and must be able
        // to put the id back, not mint a new one.
        let itemID = UUID()
        let deliveryID = UUID()
        let savedNameID = UUID()
        let dineInID = UUID()
        let scheduleID = UUID()
        let debtID = UUID()

        context.insert(Item(name: "Рис", id: itemID))
        context.insert(FoodEntry(name: "Суши", amount: 1200, id: deliveryID))
        context.insert(SavedName(value: "Суши", id: savedNameID))
        context.insert(DineInEntry(name: "Кафе", id: dineInID))
        context.insert(
            FastingEntry(startHour: 20, startMinute: 0, durationMinutes: 960, id: scheduleID)
        )
        context.insert(FastingDebt(missedMinutes: 45, id: debtID))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Item>()).first?.id == itemID)
        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).first?.id == deliveryID)
        #expect(try context.fetch(FetchDescriptor<SavedName>()).first?.id == savedNameID)
        #expect(try context.fetch(FetchDescriptor<DineInEntry>()).first?.id == dineInID)
        #expect(try context.fetch(FetchDescriptor<FastingEntry>()).first?.id == scheduleID)
        #expect(try context.fetch(FetchDescriptor<FastingDebt>()).first?.id == debtID)
    }
}
