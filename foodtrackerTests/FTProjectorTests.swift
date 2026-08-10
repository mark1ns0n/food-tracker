//
//  FTProjectorTests.swift
//  foodtrackerTests
//
//  F01.07 — the same log gives the same tables, however the events turn up.
//

import CoreSync
import Foundation
import SwiftData
import Testing

@testable import foodtracker

// MARK: - Fixtures

/// Two devices, named so that a failure message says which one wrote what.
private let deviceA = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
private let deviceB = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002")!

/// An event with a chosen HLC and device — the two things `SQLiteEventStore`
/// stamps itself, and therefore the two things a single-device store can never
/// be made to vary for a test.
private func makeEvent(
    _ entityType: String,
    _ entityID: UUID,
    _ operation: EventOperation,
    _ payload: JSONValue = .object([:]),
    at milliseconds: UInt64,
    device: UUID = deviceA,
    id: UUID = UUID()
) throws -> SyncEvent {
    try SyncEvent(
        id: id,
        schemaVersion: 1,
        entityType: entityType,
        entityID: entityID,
        operation: operation,
        payload: payload,
        hlc: HybridLogicalClock(
            physicalMilliseconds: milliseconds,
            counter: 0,
            deviceID: device
        ),
        deviceID: device,
        createdAt: Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    )
}

private func slice(_ events: [SyncEvent]) -> ProjectionSlice {
    ProjectionSlice(events: events, requiresUpgrade: false)
}

/// A log the test writes directly.
///
/// It hands events back in the order they were added, not in HLC order, so a
/// projection that came out right did so because the fold sorted — not because
/// the storage happened to.
private final class FTFixtureLog: FTEventLog {
    private(set) var events: [SyncEvent]

    init(_ events: [SyncEvent] = []) {
        self.events = events
    }

    func append(_ events: [SyncEvent]) {
        self.events.append(contentsOf: events)
    }

    func projection(
        entityType: String,
        entityID: UUID,
        supportedSchemaVersion: Int
    ) throws -> ProjectionSlice {
        make(events.filter { $0.entityType == entityType && $0.entityID == entityID },
             supportedSchemaVersion: supportedSchemaVersion)
    }

    func projections(
        entityType: String,
        supportedSchemaVersion: Int
    ) throws -> [EntityProjectionSlice] {
        Dictionary(grouping: events.filter { $0.entityType == entityType }, by: \.entityID)
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map {
                EntityProjectionSlice(
                    entityID: $0.key,
                    projection: make($0.value, supportedSchemaVersion: supportedSchemaVersion)
                )
            }
    }

    private func make(_ events: [SyncEvent], supportedSchemaVersion: Int) -> ProjectionSlice {
        let supported = events.filter { $0.schemaVersion <= supportedSchemaVersion }
        return ProjectionSlice(
            events: supported,
            requiresUpgrade: supported.count != events.count
        )
    }
}

@MainActor
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

/// Everything the six tables hold, flattened and sorted — two contexts built
/// from the same log have to produce the same lines.
@MainActor
private func snapshot(_ context: ModelContext) throws -> [String] {
    func stamp(_ date: Date) -> String {
        String(format: "%.3f", date.timeIntervalSince1970)
    }

    var lines: [String] = []
    lines += try context.fetch(FetchDescriptor<Item>()).map {
        "grocery \($0.id) \($0.name) \($0.status.rawValue) \($0.groceryType.rawValue) \(stamp($0.createdAt))"
    }
    lines += try context.fetch(FetchDescriptor<FoodEntry>()).map {
        "delivery \($0.id) \($0.name) \($0.amount) \(stamp($0.createdAt))"
    }
    lines += try context.fetch(FetchDescriptor<DineInEntry>()).map {
        "dineIn \($0.id) \($0.name) \(stamp($0.createdAt))"
    }
    lines += try context.fetch(FetchDescriptor<SavedName>()).map {
        "savedName \($0.id) \($0.value) \(stamp($0.lastUsed))"
    }
    lines += try context.fetch(FetchDescriptor<FastingEntry>()).map {
        "schedule \($0.id) \($0.startHour):\($0.startMinute) \($0.durationMinutes) "
            + ($0.activeStartDate.map(stamp) ?? "idle")
    }
    lines += try context.fetch(FetchDescriptor<FastingDebt>()).map {
        "debt \($0.id) \($0.missedMinutes) \(stamp($0.createdAt))"
    }
    return lines.sorted()
}

// MARK: - The fold

/// The rules that make a replay deterministic live in the fold, so they are
/// checked there — with fixture events from two devices at chosen HLCs, which
/// is something no single-device event store can produce.
struct FTProjectionFoldTests {
    private let groceryID = UUID(uuidString: "00000000-0000-4000-8000-0000000000a1")!
    private let scheduleID = FTIDs.fastingSchedule()
    private let moment = Date(timeIntervalSince1970: 1_770_000_000)

    private func groceryCreate(at milliseconds: UInt64) throws -> SyncEvent {
        try makeEvent(
            FTEntity.grocery,
            groceryID,
            .create,
            FTGroceryPayload(name: "Рис", status: .available, type: .side, createdAt: moment).value,
            at: milliseconds
        )
    }

    @Test
    func aShuffledArrivalProjectsExactlyLikeAnOrderedOne() throws {
        let create = try groceryCreate(at: 1_000)
        let toggle = try makeEvent(
            FTEntity.grocery,
            groceryID,
            .update,
            FTGroceryPayload(status: .used).value,
            at: 2_000
        )
        let rename = try makeEvent(
            FTEntity.grocery,
            groceryID,
            .update,
            FTGroceryPayload(name: "Гречка").value,
            at: 3_000
        )

        let ordered = try FTGroceryProjection.project(
            slice([create, toggle, rename]),
            entityID: groceryID
        )
        let shuffled = try FTGroceryProjection.project(
            slice([rename, create, toggle]),
            entityID: groceryID
        )

        #expect(ordered == shuffled)
        #expect(ordered?.name == "Гречка")
        #expect(ordered?.status == .used)
    }

    @Test
    func aToggleTouchesOnlyTheStatus() throws {
        let create = try groceryCreate(at: 1_000)
        let toggle = try makeEvent(
            FTEntity.grocery,
            groceryID,
            .update,
            FTGroceryPayload(status: .used).value,
            at: 2_000
        )

        let projection = try FTGroceryProjection.project(slice([create, toggle]), entityID: groceryID)

        #expect(projection?.status == .used)
        #expect(projection?.name == "Рис")
        #expect(projection?.type == .side)
        #expect(projection?.createdAt == moment)
    }

    @Test
    func twoDevicesSettingUpTheScheduleGiveOneEntityAndTheLaterOneWins() throws {
        // Both devices legitimately hold their own schedule before the first
        // sync, and both back it up under the same deterministic entity id
        // (F01.06). One row has to come out, not two.
        let fromA = try makeEvent(
            FTEntity.fastingSchedule,
            scheduleID,
            .create,
            FTFastingSchedulePayload(startHour: 20, startMinute: 0, durationMinutes: 960).value,
            at: 1_000,
            device: deviceA
        )
        let fromB = try makeEvent(
            FTEntity.fastingSchedule,
            scheduleID,
            .create,
            FTFastingSchedulePayload(startHour: 21, startMinute: 30, durationMinutes: 900).value,
            at: 2_000,
            device: deviceB
        )

        let projection = try FTFastingScheduleProjection.project(
            slice([fromB, fromA]),
            entityID: scheduleID
        )

        #expect(projection?.entityID == scheduleID)
        #expect(projection?.startHour == 21)
        #expect(projection?.startMinute == 30)
        #expect(projection?.durationMinutes == 900)
    }

    @Test
    func aCreateAfterADeleteResurrectsTheSchedule() throws {
        // "Change Settings" deletes and sets up again — a normal edge case of
        // the event model (B01), not a conflict.
        let setUp = try makeEvent(
            FTEntity.fastingSchedule,
            scheduleID,
            .create,
            FTFastingSchedulePayload(startHour: 20, startMinute: 0, durationMinutes: 960).value,
            at: 1_000
        )
        let tornDown = try makeEvent(FTEntity.fastingSchedule, scheduleID, .delete, at: 2_000)
        let setUpAgain = try makeEvent(
            FTEntity.fastingSchedule,
            scheduleID,
            .create,
            FTFastingSchedulePayload(startHour: 8, startMinute: 15, durationMinutes: 600).value,
            at: 3_000
        )

        let projection = try FTFastingScheduleProjection.project(
            slice([setUp, tornDown, setUpAgain]),
            entityID: scheduleID
        )

        #expect(projection?.startHour == 8)
        #expect(projection?.durationMinutes == 600)
    }

    @Test
    func anUpdateNewerThanTheDeleteIsDropped() throws {
        // The delete stays in the slice forever, so the projector needs no
        // tombstone of its own: an update lands on nothing and goes nowhere.
        let create = try groceryCreate(at: 1_000)
        let removed = try makeEvent(FTEntity.grocery, groceryID, .delete, at: 2_000)
        let lateToggle = try makeEvent(
            FTEntity.grocery,
            groceryID,
            .update,
            FTGroceryPayload(status: .used).value,
            at: 3_000
        )

        let projection = try FTGroceryProjection.project(
            slice([create, removed, lateToggle]),
            entityID: groceryID
        )

        #expect(projection == nil)
    }

    @Test
    func anExplicitNullStopsTheFastAndAnAbsentKeyLeavesItRunning() throws {
        let setUp = try makeEvent(
            FTEntity.fastingSchedule,
            scheduleID,
            .create,
            FTFastingSchedulePayload(startHour: 20, startMinute: 0, durationMinutes: 960).value,
            at: 1_000
        )
        let started = try makeEvent(
            FTEntity.fastingSchedule,
            scheduleID,
            .update,
            FTFastingSchedulePayload(activeStartDate: .some(moment)).value,
            at: 2_000
        )
        let retimed = try makeEvent(
            FTEntity.fastingSchedule,
            scheduleID,
            .update,
            FTFastingSchedulePayload(durationMinutes: 900).value,
            at: 3_000
        )
        let ate = try makeEvent(
            FTEntity.fastingSchedule,
            scheduleID,
            .update,
            FTFastingSchedulePayload(activeStartDate: .some(nil)).value,
            at: 4_000
        )

        let running = try FTFastingScheduleProjection.project(
            slice([setUp, started, retimed]),
            entityID: scheduleID
        )
        #expect(running?.activeStartDate == moment)
        #expect(running?.durationMinutes == 900)

        let stopped = try FTFastingScheduleProjection.project(
            slice([setUp, started, retimed, ate]),
            entityID: scheduleID
        )
        #expect(stopped?.activeStartDate == nil)
        #expect(stopped?.durationMinutes == 900)
    }

    @Test
    func aCreateMissingHalfItsFieldsIsRefusedRatherThanGuessed() throws {
        let eventID = UUID(uuidString: "00000000-0000-4000-8000-0000000000e1")!
        let broken = try makeEvent(
            FTEntity.grocery,
            groceryID,
            .create,
            FTGroceryPayload(name: "Рис").value,
            at: 1_000,
            id: eventID
        )

        #expect(throws: FTProjectionError.incompleteCreate(eventID)) {
            _ = try FTGroceryProjection.project(slice([broken]), entityID: groceryID)
        }
    }

    @Test
    func aSliceHeldBackByASchemaThisBuildCannotReadRefusesToProject() throws {
        // The mechanism F01.14 needs: a newer client's events block the entity
        // instead of projecting half of it.
        let held = ProjectionSlice(events: [], requiresUpgrade: true)

        #expect(throws: FTProjectionError.requiresUpgrade(FTEntity.grocery, groceryID)) {
            _ = try FTGroceryProjection.project(held, entityID: groceryID)
        }
    }
}

// MARK: - The projector

@MainActor
struct FTProjectorTests {
    private let groceryID = UUID(uuidString: "00000000-0000-4000-8000-0000000000a1")!
    private let deliveryID = UUID(uuidString: "00000000-0000-4000-8000-0000000000a2")!
    private let dineInID = UUID(uuidString: "00000000-0000-4000-8000-0000000000a3")!
    private let debtID = UUID(uuidString: "00000000-0000-4000-8000-0000000000a4")!
    private let moment = Date(timeIntervalSince1970: 1_770_000_000)

    /// One of everything, written the way the writers of F01.08–F01.10 will:
    /// row entities under their own id, the saved name and the schedule under
    /// the deterministic ids from F01.06.
    private func wholeLog() throws -> [SyncEvent] {
        [
            try makeEvent(
                FTEntity.grocery,
                groceryID,
                .create,
                FTGroceryPayload(name: "Рис", status: .available, type: .side, createdAt: moment).value,
                at: 1_000
            ),
            try makeEvent(
                FTEntity.grocery,
                groceryID,
                .update,
                FTGroceryPayload(status: .used).value,
                at: 1_100
            ),
            try makeEvent(
                FTEntity.delivery,
                deliveryID,
                .create,
                FTDeliveryPayload(name: "Суши", amount: 1_200, createdAt: moment).value,
                at: 2_000
            ),
            try makeEvent(
                FTEntity.dineIn,
                dineInID,
                .create,
                FTDineInPayload(name: "Кафе", createdAt: moment).value,
                at: 3_000
            ),
            try makeEvent(
                FTEntity.savedName,
                FTIDs.savedName(value: "Talabat"),
                .create,
                FTSavedNamePayload(value: "Talabat", lastUsed: moment).jsonValue,
                at: 4_000
            ),
            try makeEvent(
                FTEntity.fastingSchedule,
                FTIDs.fastingSchedule(),
                .create,
                FTFastingSchedulePayload(startHour: 20, startMinute: 0, durationMinutes: 960).value,
                at: 5_000
            ),
            try makeEvent(
                FTEntity.fastingDebt,
                debtID,
                .create,
                FTFastingDebtPayload(missedMinutes: 45, createdAt: moment).value,
                at: 6_000
            ),
        ]
    }

    @Test
    func aReplayBuildsAllSixTables() throws {
        let log = FTFixtureLog(try wholeLog())
        let context = try makeContext()

        try FTProjector(eventLog: log, modelContext: context).replayAll()

        let groceries = try context.fetch(FetchDescriptor<Item>())
        #expect(groceries.count == 1)
        #expect(groceries.first?.id == groceryID)
        #expect(groceries.first?.status == .used)
        #expect(groceries.first?.groceryType == .side)

        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).first?.amount == 1_200)
        #expect(try context.fetch(FetchDescriptor<DineInEntry>()).first?.name == "Кафе")
        #expect(try context.fetch(FetchDescriptor<SavedName>()).first?.value == "Talabat")
        #expect(try context.fetch(FetchDescriptor<FastingEntry>()).first?.durationMinutes == 960)
        #expect(try context.fetch(FetchDescriptor<FastingDebt>()).first?.missedMinutes == 45)
    }

    @Test
    func aReplayDropsARowTheLogDoesNotAccountFor() throws {
        // What makes a replay a rebuild rather than a merge: after it, the
        // tables hold what the events say and nothing else.
        let log = FTFixtureLog(try wholeLog())
        let context = try makeContext()
        context.insert(Item(name: "Осталось от бэкапа"))
        try context.save()

        try FTProjector(eventLog: log, modelContext: context).replayAll()

        let groceries = try context.fetch(FetchDescriptor<Item>())
        #expect(groceries.count == 1)
        #expect(groceries.first?.name == "Рис")
    }

    @Test
    func applyingEventsOneBatchAtATimeMatchesAFullReplay() throws {
        // The writer appends and applies; a device that has been away replays.
        // Those two paths are only allowed to end up in the same place.
        let events = try wholeLog()

        let incrementalLog = FTFixtureLog()
        let incrementalContext = try makeContext()
        let incremental = FTProjector(eventLog: incrementalLog, modelContext: incrementalContext)
        for event in events {
            incrementalLog.append([event])
            try incremental.apply([event])
        }

        let replayedContext = try makeContext()
        try FTProjector(eventLog: FTFixtureLog(events), modelContext: replayedContext).replayAll()

        #expect(try snapshot(incrementalContext) == (try snapshot(replayedContext)))
    }

    @Test
    func applyingADeleteRemovesTheRowAndApplyingItTwiceIsHarmless() throws {
        let create = try makeEvent(
            FTEntity.grocery,
            groceryID,
            .create,
            FTGroceryPayload(name: "Рис", status: .available, type: .main, createdAt: moment).value,
            at: 1_000
        )
        let removed = try makeEvent(FTEntity.grocery, groceryID, .delete, at: 2_000)

        let log = FTFixtureLog([create])
        let context = try makeContext()
        let projector = FTProjector(eventLog: log, modelContext: context)

        try projector.apply([create])
        #expect(try context.fetch(FetchDescriptor<Item>()).count == 1)

        log.append([removed])
        try projector.apply([removed])
        try projector.apply([removed])
        #expect(try context.fetch(FetchDescriptor<Item>()).isEmpty)
    }

    @Test
    func anEventThatIsNotInTheLogYetIsRefused() throws {
        // `apply` says which entities moved; the state still comes from the log.
        // Projecting an event that was never appended would build a row the next
        // replay silently deletes.
        let eventID = UUID(uuidString: "00000000-0000-4000-8000-0000000000e2")!
        let stray = try makeEvent(
            FTEntity.grocery,
            groceryID,
            .create,
            FTGroceryPayload(name: "Рис", status: .available, type: .main, createdAt: moment).value,
            at: 1_000,
            id: eventID
        )
        let projector = FTProjector(eventLog: FTFixtureLog(), modelContext: try makeContext())

        #expect(throws: FTProjectorError.eventNotStored(eventID)) {
            try projector.apply([stray])
        }
    }

    @Test
    func anEntityTypeThatIsNotOursIsRefused() throws {
        let foreign = try makeEvent("ban.MealCompletion", groceryID, .create, at: 1_000)
        let projector = FTProjector(eventLog: FTFixtureLog([foreign]), modelContext: try makeContext())

        #expect(throws: FTProjectorError.unexpectedEntityType("ban.MealCompletion")) {
            try projector.apply([foreign])
        }
    }
}
