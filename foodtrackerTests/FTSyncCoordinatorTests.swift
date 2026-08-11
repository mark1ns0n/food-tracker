//
//  FTSyncCoordinatorTests.swift
//  foodtrackerTests
//
//  F01.15 — the push the owner asks for by hand obeys the same two conditions
//  as the ones nobody asks for.
//

import AppShell
import CoreSync
import Foundation
import SwiftData
import Testing

@testable import foodtracker

// MARK: - Fixture

@MainActor
private final class FTNotificationSpy: FTFastingNotificationScheduling {
    func apply(_: FTFastingNotificationPlan) {}
}

/// Counts what the coordinator asked the backend to do, and what the router knew
/// at the moment it asked.
private actor FTSyncSpy {
    private(set) var attempts = 0
    private(set) var routingSummaries: [ProjectorRoutingSummary] = []

    func recordAttempt() {
        attempts += 1
    }

    func record(_ summary: ProjectorRoutingSummary) {
        routingSummaries.append(summary)
    }
}

/// A real store and a real router behind a `SyncBootstrap` whose network half is
/// a closure. That is the whole point: everything the coordinator actually
/// decides — the backfill gate, the wait on registration — is on this side of
/// the transport, and none of it needs a keychain or a server.
@MainActor
private struct FTCoordinatorFixture {
    let store: SQLiteEventStore
    let context: ModelContext
    let writer: FTWriter
    let bootstrap: SyncBootstrap
    let coordinator: FTSyncCoordinator
    let spy: FTSyncSpy
    let defaults: UserDefaults

    /// `probeRouting` makes the registration invariant observable: the stub
    /// pushes one `ft.*` event through the router from inside the sync call, so
    /// a run that started before registration would record it as unhandled.
    init(backfillDone: Bool, authorized: Bool = true) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let deviceID = UUID()
        store = try SQLiteEventStore(
            databaseURL: directory.appendingPathComponent("CoreSync.sqlite"),
            deviceID: deviceID
        )

        let schema = Schema([
            Item.self,
            FoodEntry.self,
            SavedName.self,
            DineInEntry.self,
            FastingEntry.self,
            FastingDebt.self,
        ])
        context = ModelContext(
            try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        )

        let projector = FTProjector(eventLog: store, modelContext: context)
        writer = FTWriter(modelContext: context, store: store, projector: projector)

        let router = try EventProjectorRouter()
        let spy = FTSyncSpy()
        self.spy = spy
        bootstrap = SyncBootstrap(
            deviceID: deviceID,
            eventStore: store,
            projectorRouter: router,
            authorizationAvailable: { authorized },
            synchronize: { _ in
                await spy.recordAttempt()
                await spy.record(await router.route([try FTCoordinatorFixture.probe(deviceID)]))
                return SyncSummary(
                    submittedEventCount: 1,
                    receivedEventCount: 0,
                    finalServerSequence: 1,
                    pages: 1
                )
            }
        )

        // A suite of its own: `.standard` is shared with whatever else the test
        // process has already written, and this flag decides whether syncing is
        // allowed at all.
        defaults = UserDefaults(suiteName: "ft.tests.\(UUID().uuidString)")!
        defaults.set(backfillDone, forKey: FTBackfillService.doneKey)

        coordinator = FTSyncCoordinator(
            bootstrap: bootstrap,
            handler: FTRemoteEventHandler(
                eventLog: store,
                projector: projector,
                notifications: FTNotificationSpy()
            ),
            defaults: defaults
        )
    }

    /// An `ft.*` event that exists only to be routed. The handler will fail to
    /// project it — it is not in the store — and swallow that per entity, which
    /// is exactly what F01.14 built; routing still counts it as dispatched.
    private static func probe(_ deviceID: UUID) throws -> SyncEvent {
        let stamp = UInt64(Date().timeIntervalSince1970 * 1_000)
        return try SyncEvent(
            id: UUID(),
            schemaVersion: FTEntity.schemaVersion,
            entityType: FTEntity.grocery,
            entityID: UUID(),
            operation: .create,
            payload: .object([:]),
            hlc: HybridLogicalClock(
                physicalMilliseconds: stamp,
                counter: 0,
                deviceID: deviceID
            ),
            deviceID: deviceID,
            createdAt: Date(),
            serverSeq: 1
        )
    }
}

// MARK: - Tests

@MainActor
struct FTSyncCoordinatorTests {
    /// The header rule of F01: the first sync comes after the backfill. A manual
    /// push is not an exception to it — the backend must never see fresh events
    /// with no history behind them, however the push was triggered.
    @Test
    func aManualSyncBeforeTheBackfillNeverReachesTheBackend() async throws {
        let fixture = try FTCoordinatorFixture(backfillDone: false)

        let result = await fixture.coordinator.synchronizeNow()

        #expect(result == nil)
        #expect(await fixture.spy.attempts == 0)
    }

    @Test
    func aManualSyncAfterTheBackfillPushesTheLog() async throws {
        let fixture = try FTCoordinatorFixture(backfillDone: true)

        let result = await fixture.coordinator.synchronizeNow()

        #expect(result == .synchronized(
            SyncSummary(
                submittedEventCount: 1,
                receivedEventCount: 0,
                finalServerSequence: 1,
                pages: 1
            )
        ))
        #expect(await fixture.spy.attempts == 1)
    }

    /// The coordinator registers its pull handler asynchronously, so the first
    /// sync it starts is the one that could outrun the registration. Its page
    /// would be counted unhandled and never projected — and the cursor would
    /// have moved past it.
    @Test
    func aManualSyncWaitsForTheRouterToKnowWhereFTEventsGo() async throws {
        let fixture = try FTCoordinatorFixture(backfillDone: true)

        _ = await fixture.coordinator.synchronizeNow()

        let summaries = await fixture.spy.routingSummaries
        #expect(summaries == [ProjectorRoutingSummary(
            dispatchedEventCount: 1,
            unhandledEventCount: 0
        )])
    }

    /// An unenrolled device is the ordinary state of this screen before the
    /// owner pastes a link, and it has to be distinguishable from a failure.
    @Test
    func aManualSyncOnAnUnenrolledDeviceSaysSoRatherThanFailing() async throws {
        let fixture = try FTCoordinatorFixture(backfillDone: true, authorized: false)

        let result = await fixture.coordinator.synchronizeNow()

        #expect(result == .skippedNoCredential)
    }

    @Test
    func theLogCountsAreTheStoresOwn() async throws {
        let fixture = try FTCoordinatorFixture(backfillDone: true)
        #expect(fixture.coordinator.logCounts == FTLogCounts(total: 0, pending: 0))

        _ = try fixture.writer.addGrocery(name: "Rice", type: .side)

        #expect(fixture.coordinator.logCounts == FTLogCounts(total: 1, pending: 1))
    }
}
