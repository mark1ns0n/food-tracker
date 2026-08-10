//
//  SmokeTests.swift
//  foodtrackerTests
//
//  Created for F01.01 — the app had no test target at all until this one.
//

import Foundation
import SwiftData
import Testing

@testable import foodtracker

/// The floor every later F01 test stands on: the app's schema builds, and each
/// of the six models survives a save/fetch round trip.
///
/// Worth its own test because phases 1–2 replay events into exactly this
/// container — a schema that cannot be opened would surface as a confusing
/// projector failure instead of what it is.
@MainActor
struct SmokeTests {
    /// The schema the app itself registers (`foodtrackerApp.sharedModelContainer`),
    /// kept in one place so a model added there and forgotten here shows up as a
    /// count mismatch rather than silently going untested.
    private static let models: [any PersistentModel.Type] = [
        Item.self,
        FoodEntry.self,
        SavedName.self,
        DineInEntry.self,
        FastingEntry.self,
        FastingDebt.self,
    ]

    @Test
    func everyModelInTheSchemaRoundTripsThroughAnInMemoryStore() throws {
        let schema = Schema(Self.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        context.insert(Item(name: "Рис"))
        context.insert(FoodEntry(name: "Суши", amount: 1200))
        context.insert(SavedName(value: "Суши"))
        context.insert(DineInEntry(name: "Кафе"))
        context.insert(FastingEntry(startHour: 20, startMinute: 0, durationMinutes: 16 * 60))
        context.insert(FastingDebt(missedMinutes: 45))
        try context.save()

        let items = try context.fetch(FetchDescriptor<Item>())
        let deliveries = try context.fetch(FetchDescriptor<FoodEntry>())
        let savedNames = try context.fetch(FetchDescriptor<SavedName>())
        let dineIns = try context.fetch(FetchDescriptor<DineInEntry>())
        let schedules = try context.fetch(FetchDescriptor<FastingEntry>())
        let debts = try context.fetch(FetchDescriptor<FastingDebt>())

        #expect(items.count == 1)
        #expect(deliveries.count == 1)
        #expect(savedNames.count == 1)
        #expect(dineIns.count == 1)
        #expect(schedules.count == 1)
        #expect(debts.count == 1)

        #expect(items.first?.name == "Рис")
        #expect(deliveries.first?.amount == 1200)
        #expect(schedules.first?.durationMinutes == 960)
        #expect(debts.first?.missedMinutes == 45)
    }
}
