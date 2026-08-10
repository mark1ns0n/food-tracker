//
//  FTSyncComposition.swift
//  foodtracker
//
//  F01.05 — the app gets the shared event log.
//  F01.13 — and the transport that pushes it.
//

import AppShell
import CoreSync
import Foundation
import OSLog

/// Where foodtracker's event log lives, and how it reaches the backend.
enum FTSyncComposition {
    /// Also the Application Support folder the log is stored under.
    static let applicationIdentifier = "com.mark1ns0n.foodtracker"

    /// foodtracker enrolls as a device of its own, so its device id lives in its
    /// own keychain namespace — sharing one with super-app or beerCalculator
    /// would make two apps claim the same device in the log.
    static let keychainService = "com.mark1ns0n.foodtracker.sync"

    /// The same fixed origin as kopilka and beerCalculator (K01/E01), not an
    /// Info.plist key: there is one backend, and a URL that can be varied per
    /// build is a knob nothing turns.
    static let syncOrigin = URL(string: "https://sync.hardibardi.com")!

    /// The whole sync stack: the same store `makeEventStore()` opens, plus the
    /// transport and the DPoP device authorization. `.dpopOnly` is not a choice
    /// any more the way it was in K01/E01 — B20 closed the legacy path on the
    /// server in 2026-08, so a bearer client could never sync at all.
    ///
    /// `nil` means the stack could not be composed (keychain trouble, usually).
    /// The app then falls back to the bare local store and stays fully
    /// offline-functional, which is the failure mode the card asks for.
    static func makeSyncBootstrap() -> SyncBootstrap? {
        try? SyncBootstrap.live(
            configuration: LiveSyncConfiguration(
                applicationIdentifier: applicationIdentifier,
                keychainService: keychainService,
                baseURL: syncOrigin,
                capabilities: FTEntity.capabilities,
                deviceAuthorization: LiveDeviceAuthorizationConfiguration(),
                authorizationMode: .dpopOnly
            )
        )
    }

    static func makeEventStore() throws -> SQLiteEventStore {
        let deviceID = try KeychainDeviceIdentityStore(service: keychainService)
            .loadOrCreateDeviceID()
        return try SQLiteEventStore(
            databaseURL: SQLiteEventStore.applicationSupportURL(
                applicationIdentifier: applicationIdentifier
            ),
            deviceID: deviceID
        )
    }
}
