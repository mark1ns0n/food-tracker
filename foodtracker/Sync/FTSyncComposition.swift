//
//  FTSyncComposition.swift
//  foodtracker
//
//  F01.05 — the app gets the shared event log. Nothing writes to it yet.
//

import CoreSync
import Foundation
import OSLog

/// Where foodtracker's event log lives.
///
/// Only the local half of CoreSync is wired here. Transport, enrollment and the
/// sync coordinator belong to phase 3 (`F01.13`) and are gated on the backend;
/// phases 1–2 are entirely offline, so nothing in this file reaches the network.
enum FTSyncComposition {
    /// Also the Application Support folder the log is stored under.
    static let applicationIdentifier = "com.mark1ns0n.foodtracker"

    /// foodtracker enrolls as a device of its own, so its device id lives in its
    /// own keychain namespace — sharing one with super-app or beerCalculator
    /// would make two apps claim the same device in the log.
    static let keychainService = "com.mark1ns0n.foodtracker.sync"

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
