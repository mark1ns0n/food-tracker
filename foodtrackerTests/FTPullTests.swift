//
//  FTPullTests.swift
//  foodtrackerTests
//
//  F01.14 — what another device did shows up here.
//

import CoreSync
import Foundation
import SwiftData
import Testing

@testable import foodtracker

// MARK: - Fixtures

/// This device, and the one whose events keep arriving.
private let localDevice = UUID(uuidString: "aaaaaaaa-0000-4000-8000-00000000000a")!
private let remoteDevice = UUID(uuidString: "bbbbbbbb-0000-4000-8000-00000000000b")!

/// The card asks for `store.merge(remote:)`; the store has no such method — a
/// merge only happens inside `SyncEngine`, against a `SyncResponse`. So the
/// remote page arrives the way the real one does: through a transport that
/// answers with it, into a real `SQLiteEventStore`, with nothing stubbed
/// between the wire format and the tables.
private actor FTStubTransport: SyncTransport {
    private var responses: [SyncResponse]

    init(_ responses: [SyncResponse]) {
        self.responses = responses
    }

    func synchronize(request _: SyncRequest) async throws -> SyncResponse {
        guard !responses.isEmpty else { throw FTStubTransportError.noResponseScripted }
        return responses.removeFirst()
    }
}

private enum FTStubTransportError: Error {
    case noResponseScripted
}

/// Records what was planned instead of asking the user for permission to
/// deliver it.
@MainActor
private final class FTNotificationSpy: FTFastingNotificationScheduling {
    private(set) var plans: [FTFastingNotificationPlan] = []

    func apply(_ plan: FTFastingNotificationPlan) {
        plans.append(plan)
    }
}

/// The clock the handler reads, and the base the fixture HLCs are built from —
/// far enough from `Date()` to stay honest, close enough that the store does not
/// log a five-minute skew warning for every event.
private let fixedNow = Date(timeIntervalSince1970: 1_786_000_000)

private func milliseconds(_ offsetSeconds: Int) -> UInt64 {
    UInt64((fixedNow.timeIntervalSince1970 + Double(offsetSeconds)) * 1_000)
}

/// An event as the server hands it back: written by the other device, and
/// carrying the sequence number that is what a page is ordered by.
private func remoteEvent(
    _ entityType: String,
    _ entityID: UUID,
    _ operation: EventOperation,
    _ payload: JSONValue = .object([:]),
    serverSeq: Int64,
    schemaVersion: Int = FTEntity.schemaVersion,
    device: UUID = remoteDevice
) throws -> SyncEvent {
    let stamp = milliseconds(Int(serverSeq))
    return try SyncEvent(
        id: UUID(),
        schemaVersion: schemaVersion,
        entityType: entityType,
        entityID: entityID,
        operation: operation,
        payload: payload,
        hlc: HybridLogicalClock(
            physicalMilliseconds: stamp,
            counter: 0,
            deviceID: device
        ),
        deviceID: device,
        createdAt: Date(timeIntervalSince1970: Double(stamp) / 1_000),
        serverSeq: serverSeq
    )
}

private func page(_ events: [SyncEvent]) throws -> SyncResponse {
    try SyncResponse(
        events: events,
        newServerSeq: events.last?.serverSeq ?? 0,
        hasMore: false
    )
}

/// The whole pull path over a real store: transport → engine → merge →
/// handler → projector → tables.
@MainActor
private struct FTPullHarness {
    let store: SQLiteEventStore
    let context: ModelContext
    let notifications: FTNotificationSpy
    private let engine: SyncEngine

    init(responses: [SyncResponse]) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = try SQLiteEventStore(
            databaseURL: directory.appendingPathComponent("CoreSync.sqlite"),
            deviceID: localDevice
        )

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
        context = ModelContext(container)

        notifications = FTNotificationSpy()
        let handler = FTRemoteEventHandler(
            eventLog: store,
            projector: FTProjector(eventLog: store, modelContext: context),
            notifications: notifications,
            now: { fixedNow }
        )
        engine = try SyncEngine(
            store: store,
            transport: FTStubTransport(responses),
            capabilities: FTEntity.capabilities,
            onNewRemoteEvents: { events in
                await handler.handle(events)
            }
        )
    }

    func pull() async throws {
        _ = try await engine.synchronize(deviceID: localDevice)
    }

    func fetch<Model: PersistentModel>(_: Model.Type) throws -> [Model] {
        try context.fetch(FetchDescriptor<Model>())
    }
}

// MARK: - Tests

@MainActor
struct FTPullTests {
    private let groceryID = UUID()
    private let deliveryID = UUID()
    private let dineInID = UUID()

    /// One page holding a bit of everything the other device can produce.
    private func firstPage() throws -> [SyncEvent] {
        let createdAt = Date(timeIntervalSince1970: 1_785_900_000)
        return [
            try remoteEvent(
                FTEntity.grocery,
                groceryID,
                .create,
                FTGroceryPayload(
                    name: "Рис",
                    status: .available,
                    type: .side,
                    createdAt: createdAt
                ).value,
                serverSeq: 1
            ),
            // The toggle the user made on the other device, as its own event.
            try remoteEvent(
                FTEntity.grocery,
                groceryID,
                .update,
                FTGroceryPayload(status: .used).value,
                serverSeq: 2
            ),
            try remoteEvent(
                FTEntity.delivery,
                deliveryID,
                .create,
                FTDeliveryPayload(name: "Talabat", amount: 12.5, createdAt: createdAt).value,
                serverSeq: 3
            ),
            try remoteEvent(
                FTEntity.dineIn,
                dineInID,
                .create,
                FTDineInPayload(name: "Burger King", createdAt: createdAt).value,
                serverSeq: 4
            ),
            try remoteEvent(
                FTEntity.savedName,
                FTIDs.savedName(value: "Talabat"),
                .create,
                FTSavedNamePayload(value: "Talabat", lastUsed: createdAt).jsonValue,
                serverSeq: 5
            ),
        ]
    }

    @Test
    func aPageFromAnotherDeviceReachesTheTables() async throws {
        let harness = try FTPullHarness(responses: [try page(try firstPage())])
        try await harness.pull()

        let groceries = try harness.fetch(Item.self)
        #expect(groceries.count == 1)
        #expect(groceries.first?.id == groceryID)
        #expect(groceries.first?.name == "Рис")
        // The update was in the same page as the create: the fold reads the
        // entity's whole slice, so the row shows the state after both.
        #expect(groceries.first?.status == .used)
        #expect(groceries.first?.groceryType == .side)

        let deliveries = try harness.fetch(FoodEntry.self)
        #expect(deliveries.count == 1)
        #expect(deliveries.first?.name == "Talabat")
        #expect(deliveries.first?.amount == 12.5)

        #expect(try harness.fetch(DineInEntry.self).map(\.name) == ["Burger King"])
        #expect(try harness.fetch(SavedName.self).map(\.value) == ["Talabat"])

        // No `ft.FastingSchedule` in the page, so nothing was re-planned: a pull
        // that never mentioned the schedule must not touch a pending reminder.
        #expect(harness.notifications.plans.isEmpty)
    }

    @Test
    func theSamePageDeliveredAgainChangesNothing() async throws {
        let events = try firstPage()
        // The server would not resend a page, but a device that lost its cursor
        // gets the same events under new sequence numbers. Dedup is by event id,
        // so the log must hold five events either way.
        let again = try events.enumerated().map { index, event in
            try SyncEvent(
                id: event.id,
                schemaVersion: event.schemaVersion,
                entityType: event.entityType,
                entityID: event.entityID,
                operation: event.operation,
                payload: event.payload,
                hlc: event.hlc,
                deviceID: event.deviceID,
                createdAt: event.createdAt,
                serverSeq: Int64(events.count + index + 1)
            )
        }

        let harness = try FTPullHarness(responses: [try page(events), try page(again)])
        try await harness.pull()
        let afterFirst = try harness.fetch(Item.self).map(\.persistentModelID)

        try await harness.pull()

        #expect(try harness.store.eventCount() == events.count)
        #expect(try harness.fetch(Item.self).count == 1)
        #expect(try harness.fetch(Item.self).first?.status == .used)
        // The same row, updated in place — not a second one beside it.
        #expect(try harness.fetch(Item.self).map(\.persistentModelID) == afterFirst)
        #expect(try harness.fetch(FoodEntry.self).count == 1)
        #expect(try harness.fetch(DineInEntry.self).count == 1)
        #expect(try harness.fetch(SavedName.self).count == 1)
    }

    @Test
    func aScheduleThatArrivesReplansTheReminder() async throws {
        let scheduleID = FTIDs.fastingSchedule()
        let started = fixedNow.addingTimeInterval(-30 * 60)

        let setUp = try page([
            try remoteEvent(
                FTEntity.fastingSchedule,
                scheduleID,
                .create,
                FTFastingSchedulePayload(
                    startHour: 20,
                    startMinute: 0,
                    durationMinutes: 60
                ).value,
                serverSeq: 1
            )
        ])
        let fastStarted = try page([
            try remoteEvent(
                FTEntity.fastingSchedule,
                scheduleID,
                .update,
                FTFastingSchedulePayload(activeStartDate: .some(started)).value,
                serverSeq: 2
            )
        ])
        let thrownAway = try page([
            try remoteEvent(FTEntity.fastingSchedule, scheduleID, .delete, serverSeq: 3)
        ])

        let harness = try FTPullHarness(responses: [setUp, fastStarted, thrownAway])

        try await harness.pull()
        #expect(try harness.fetch(FastingEntry.self).count == 1)
        #expect(try harness.fetch(FastingEntry.self).first?.startHour == 20)
        #expect(harness.notifications.plans == [.start(hour: 20, minute: 0)])

        // Started on the other device half an hour ago: what is left of the
        // hour is what this device has to remind about, not the whole of it.
        try await harness.pull()
        #expect(try harness.fetch(FastingEntry.self).first?.activeStartDate == started)
        #expect(harness.notifications.plans.last == .end(after: 30 * 60))

        try await harness.pull()
        #expect(try harness.fetch(FastingEntry.self).isEmpty)
        #expect(harness.notifications.plans.last == FTFastingNotificationPlan.none)
    }

    @Test
    func oneEntityThisBuildCannotReadDoesNotStopTheRest() async throws {
        let futureGrocery = UUID()
        let readableGrocery = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_785_900_000)

        let harness = try FTPullHarness(responses: [
            try page([
                // Written by a client that knows a newer payload.
                try remoteEvent(
                    FTEntity.grocery,
                    futureGrocery,
                    .create,
                    FTGroceryPayload(
                        name: "Гречка",
                        status: .available,
                        type: .main,
                        createdAt: createdAt
                    ).value,
                    serverSeq: 1,
                    schemaVersion: FTEntity.schemaVersion + 1
                ),
                // An entity type this build has never heard of.
                try remoteEvent(
                    "ft.Whatever",
                    UUID(),
                    .create,
                    .object(["name": .string("?")]),
                    serverSeq: 2
                ),
                try remoteEvent(
                    FTEntity.grocery,
                    readableGrocery,
                    .create,
                    FTGroceryPayload(
                        name: "Рис",
                        status: .available,
                        type: .side,
                        createdAt: createdAt
                    ).value,
                    serverSeq: 3
                ),
            ])
        ])

        try await harness.pull()

        // The unreadable two are in the log and blocked, not dropped — and the
        // third one landed anyway, which is the whole point: the page moves the
        // cursor, so an entity skipped here is not re-offered later.
        #expect(try harness.store.eventCount() == 3)
        #expect(try harness.store.upgradeRequirements().count == 2)
        #expect(try harness.fetch(Item.self).map(\.id) == [readableGrocery])
    }
}
