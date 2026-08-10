//
//  CoreSyncSmokeTests.swift
//  foodtrackerTests
//
//  F01.05 — the shared event log is reachable from this app.
//

import CoreSync
import Foundation
import Testing

@testable import foodtracker

/// What F01 assumes about CoreSync, pinned against the package as it actually
/// is rather than as Part 2 of the card described it.
///
/// Two things it checks: an `ft.*` event can be written at all, and the store —
/// not the caller — is what stamps the HLC and the device id. Everything in
/// phases 1–2 rests on that stamping being automatic.
struct CoreSyncSmokeTests {
    private func makeStore(deviceID: UUID) throws -> SQLiteEventStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try SQLiteEventStore(
            databaseURL: directory.appendingPathComponent("CoreSync.sqlite"),
            deviceID: deviceID
        )
    }

    @Test
    func anAppendedEventComesBackStampedWithTheHLCAndTheDevice() throws {
        let deviceID = UUID()
        let store = try makeStore(deviceID: deviceID)
        let entityID = UUID()

        let appended = try store.appendLocalEvent(
            LocalEventDraft(
                entityType: "ft.Grocery",
                entityID: entityID,
                operation: .create,
                payload: .object([
                    "name": .string("Рис"),
                    "status": .string("available"),
                ])
            )
        )

        #expect(appended.entityType == "ft.Grocery")
        #expect(appended.entityID == entityID)
        #expect(appended.deviceID == deviceID)
        #expect(appended.hlc.deviceID == deviceID)
        #expect(appended.hlc.physicalMilliseconds > 0)
        // Not yet pushed anywhere: the server assigns this on first sync (F01.13).
        #expect(appended.serverSeq == nil)
    }

    @Test
    func theEventIsReadableBackOutOfTheStore() throws {
        let store = try makeStore(deviceID: UUID())
        let entityID = UUID()

        _ = try store.appendLocalEvent(
            LocalEventDraft(
                entityType: "ft.Grocery",
                entityID: entityID,
                operation: .create,
                payload: .object(["name": .string("Гречка")])
            )
        )

        // Reading is per entity type/id — there is no prefix query on the store,
        // which is why the projectors in F01.07 are written per entity type.
        let slice = try store.projection(
            entityType: "ft.Grocery",
            entityID: entityID,
            supportedSchemaVersion: 1
        )

        #expect(slice.requiresUpgrade == false)
        #expect(slice.events.count == 1)
        #expect(slice.events.first?.payload == .object(["name": .string("Гречка")]))

        let everyGrocery = try store.projections(
            entityType: "ft.Grocery",
            supportedSchemaVersion: 1
        )
        #expect(everyGrocery.count == 1)
        #expect(everyGrocery.first?.entityID == entityID)
    }

    @Test
    func hlcOrderStrictlyIncreasesWithinOneDevice() throws {
        let store = try makeStore(deviceID: UUID())

        let first = try store.appendLocalEvent(
            LocalEventDraft(
                entityType: "ft.Grocery",
                entityID: UUID(),
                operation: .create,
                payload: .object(["name": .string("Рис")])
            )
        )
        let second = try store.appendLocalEvent(
            LocalEventDraft(
                entityType: "ft.Grocery",
                entityID: UUID(),
                operation: .create,
                payload: .object(["name": .string("Гречка")])
            )
        )

        #expect(first.hlc < second.hlc)
    }

    @Test
    func theAppsOwnCompositionOpensAStoreWithAStableDeviceID() throws {
        // The keychain namespace is this app's alone; the same id has to come
        // back on the next launch or every restart would look like a new device.
        let store = try FTSyncComposition.makeEventStore()
        let again = try FTSyncComposition.makeEventStore()

        #expect(store.deviceID == again.deviceID)
        #expect(store.databaseURL.lastPathComponent == "CoreSync.sqlite")
    }
}
