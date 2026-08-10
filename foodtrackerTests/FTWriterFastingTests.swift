//
//  FTWriterFastingTests.swift
//  foodtrackerTests
//
//  F01.10 — the fast starts, stops and is broken in the log first.
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

    func schedules() throws -> [FastingEntry] {
        try context.fetch(FetchDescriptor<FastingEntry>())
    }

    func debts() throws -> [FastingDebt] {
        try context.fetch(FetchDescriptor<FastingDebt>()).sorted { $0.createdAt < $1.createdAt }
    }

    func scheduleEvents() throws -> [SyncEvent] {
        try store.projection(
            entityType: FTEntity.fastingSchedule,
            entityID: FTIDs.fastingSchedule(),
            supportedSchemaVersion: FTEntity.schemaVersion
        ).events.sorted(by: FTFold.order)
    }

    /// A schedule set up the ordinary way, as every test below needs one.
    @discardableResult
    func setUpSchedule() throws -> FastingEntry {
        try writer.createFastingSchedule(startHour: 20, startMinute: 0, durationMinutes: 960)
        return try #require(try schedules().first)
    }

    /// The schedule as it stood before any of this existed: a row in the table
    /// and not one event about it.
    func insertLegacySchedule(activeStartDate: Date? = nil) throws {
        let entry = FastingEntry(startHour: 21, startMinute: 30, durationMinutes: 900)
        entry.activeStartDate = activeStartDate
        context.insert(entry)
        try context.save()
    }

    func snapshot(_ context: ModelContext? = nil) throws -> [String] {
        let context = context ?? self.context
        func stamp(_ date: Date?) -> String {
            date.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? "-"
        }

        var lines = try context.fetch(FetchDescriptor<FastingEntry>()).map {
            "schedule \($0.id) \($0.startHour):\($0.startMinute) \($0.durationMinutes) \(stamp($0.activeStartDate))"
        }
        lines += try context.fetch(FetchDescriptor<FastingDebt>()).map {
            "debt \($0.id) \($0.missedMinutes) \(stamp($0.createdAt))"
        }
        return lines.sorted()
    }
}

@MainActor
struct FTWriterFastingTests {
    private let noon = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: Setting up, and starting

    @Test
    func settingUpASchedulePutsOneSingletonInTheTable() throws {
        let fixture = try Fixture()

        try fixture.writer.createFastingSchedule(startHour: 20, startMinute: 0, durationMinutes: 960)

        #expect(try fixture.store.eventCount() == 1)
        let entry = try #require(try fixture.schedules().first)
        #expect(try fixture.schedules().count == 1)
        #expect(entry.startHour == 20)
        #expect(entry.durationMinutes == 960)
        #expect(entry.isFasting == false)
        // One entity id, fixed forever, so the schedule on the second device is
        // this schedule rather than a second one.
        #expect(entry.id == FTIDs.fastingSchedule())
    }

    @Test
    func startingWritesTheDateAndStoppingWritesAnExplicitNull() throws {
        let fixture = try Fixture()
        try fixture.setUpSchedule()

        try fixture.writer.startFast(at: noon)
        #expect(try fixture.schedules().first?.activeStartDate == noon)

        try fixture.writer.stopFast()
        #expect(try fixture.schedules().first?.activeStartDate == nil)

        let events = try fixture.scheduleEvents()
        #expect(events.map(\.operation) == [.create, .update, .update])
        // The stop has to say "null" out loud: an absent key would only mean
        // "this event does not mention it", and the fast would still be running
        // on the next device.
        let stop = FTFastingSchedulePayload.decode(try #require(events.last).payload)
        #expect(stop.activeStartDate == .some(.none))
    }

    // MARK: Breaking the fast

    @Test
    func iAteWithTimeLeftWritesTheDebtAndTheStopTogether() throws {
        let fixture = try Fixture()
        try fixture.setUpSchedule()
        try fixture.writer.startFast(at: noon)
        let before = try fixture.store.eventCount()

        try fixture.writer.recordIAte(missedMinutes: 30, at: noon)

        #expect(try fixture.store.eventCount() == before + 2)
        let debt = try #require(try fixture.debts().first)
        #expect(try fixture.debts().count == 1)
        #expect(debt.missedMinutes == 30)
        #expect(try fixture.schedules().first?.isFasting == false)
    }

    @Test
    func iAteWithNothingLeftOwesNothingAndWritesOnlyTheStop() throws {
        let fixture = try Fixture()
        try fixture.setUpSchedule()
        try fixture.writer.startFast(at: noon)
        let before = try fixture.store.eventCount()

        try fixture.writer.recordIAte(missedMinutes: 0, at: noon)

        #expect(try fixture.store.eventCount() == before + 1)
        #expect(try fixture.debts().isEmpty)
        #expect(try fixture.schedules().first?.isFasting == false)
    }

    // MARK: Change Settings

    @Test
    func changingTheSettingsAndSettingThemUpAgainLeavesOneSchedule() throws {
        let fixture = try Fixture()
        try fixture.setUpSchedule()

        try fixture.writer.deleteFastingSchedule()
        #expect(try fixture.schedules().isEmpty)

        try fixture.writer.createFastingSchedule(startHour: 8, startMinute: 15, durationMinutes: 600)

        // Resurrection after a tombstone (B01): the `delete` stays in the slice
        // forever, and the `create` after it starts the entity anew.
        #expect(try fixture.scheduleEvents().map(\.operation) == [.create, .delete, .create])
        let entry = try #require(try fixture.schedules().first)
        #expect(try fixture.schedules().count == 1)
        #expect(entry.startHour == 8)
        #expect(entry.durationMinutes == 600)
    }

    @Test
    func aScheduleTheUserThrewAwayIsNotResurrectedByStartingAFast() throws {
        let fixture = try Fixture()
        try fixture.setUpSchedule()
        try fixture.writer.deleteFastingSchedule()
        let before = try fixture.store.eventCount()

        #expect(throws: FTWriterError.deletedSchedule) {
            try fixture.writer.startFast(at: noon)
        }
        #expect(try fixture.store.eventCount() == before)
    }

    @Test
    func thereIsNothingToStartWithoutASchedule() throws {
        let fixture = try Fixture()

        #expect(throws: FTWriterError.unknownSchedule) {
            try fixture.writer.startFast(at: noon)
        }
        #expect(try fixture.store.eventCount() == 0)
    }

    // MARK: The schedule that predates the log

    @Test
    func aScheduleFromBeforeTheLogIsWrittenDownBeforeItIsChanged() throws {
        // Between F01.10 and the backfill of F01.11 the table holds a schedule
        // no event accounts for. Without materializing it first, the `update`
        // would fold onto nothing and the fast would silently not start.
        let fixture = try Fixture()
        try fixture.insertLegacySchedule()

        try fixture.writer.startFast(at: noon)

        let events = try fixture.scheduleEvents()
        #expect(events.map(\.operation) == [.create, .update])
        // The create carries the schedule the user actually had, not a default.
        let created = FTFastingSchedulePayload.decode(try #require(events.first).payload)
        #expect(created.startHour == 21)
        #expect(created.durationMinutes == 900)

        #expect(try fixture.schedules().count == 1)
        #expect(try fixture.schedules().first?.activeStartDate == noon)
    }

    @Test
    func aFastRunningSinceBeforeTheLogCanStillBeStopped() throws {
        let fixture = try Fixture()
        try fixture.insertLegacySchedule(activeStartDate: noon)

        try fixture.writer.stopFast()

        // The materialized create carries the running fast, so what the log
        // describes is a fast that was stopped — not a schedule that appeared
        // out of nowhere with nothing running in it.
        let created = FTFastingSchedulePayload.decode(try #require(try fixture.scheduleEvents().first).payload)
        #expect(created.activeStartDate == .some(noon))
        #expect(try fixture.schedules().count == 1)
        #expect(try fixture.schedules().first?.isFasting == false)
    }

    // MARK: The writer and the projector agree

    @Test
    func theTablesMatchAFullReplayOfEverythingTheWriterWrote() throws {
        let fixture = try Fixture()
        try fixture.setUpSchedule()
        try fixture.writer.startFast(at: noon)
        try fixture.writer.recordIAte(missedMinutes: 45, at: noon)
        try fixture.writer.startFast(at: noon.addingTimeInterval(3_600))
        try fixture.writer.stopFast()
        try fixture.writer.deleteFastingSchedule()
        try fixture.writer.createFastingSchedule(startHour: 8, startMinute: 15, durationMinutes: 600)
        try fixture.writer.startFast(at: noon.addingTimeInterval(7_200))

        let replayed = try Fixture.makeContext()
        try FTProjector(eventLog: fixture.store, modelContext: replayed).replayAll()

        #expect(try fixture.snapshot() == (try fixture.snapshot(replayed)))
        #expect(try fixture.schedules().count == 1)
        #expect(try fixture.debts().count == 1)
    }
}
