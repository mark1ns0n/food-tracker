//
//  FTSyncComposition.swift
//  foodtracker
//
//  F01.05 — the app gets the shared event log.
//  F01.13 — and the transport that pushes it.
//  F01.15 — and the way this device is allowed to use it.
//

import AppShell
import CoreSync
import Foundation
import UIKit

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

    /// Where device credentials are issued and where the owner approves this
    /// device. Fixed for the same reason `syncOrigin` is.
    static let authOrigin = URL(string: "https://auth.hardibardi.com")!

    /// One configuration serves both halves of DPoP: the bootstrap signs sync
    /// requests with the key it names, and the enrollment coordinator binds
    /// that same key. Built separately they could disagree on `keyName`, and
    /// the device would enrol one key and then sign with another.
    static let deviceAuthorization = LiveDeviceAuthorizationConfiguration(
        onReenrollmentRequired: {
            NotificationCenter.default.post(name: .ftDeviceAuthorizationRevoked, object: nil)
        }
    )

    /// `try!` on literals only — the initializer rejects a malformed origin or a
    /// client id that is not this fleet's, and both are constants right here.
    /// The alternative is an optional threaded into a screen for a failure that
    /// a build either always has or never has.
    static let enrollmentConfiguration = try! DeviceEnrollmentConfiguration(
        authOrigin: authOrigin,
        syncOrigin: syncOrigin
    )

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
                deviceAuthorization: deviceAuthorization,
                authorizationMode: .dpopOnly
            )
        )
    }

    /// Built per use rather than held: it reads the device key out of the
    /// keychain, and `DeviceEnrollmentCoordinator` is a value with no state of
    /// its own between calls — everything it learns it writes back to the
    /// keychain, which is also where the bootstrap looks.
    static func makeEnrollmentCoordinator() throws -> DeviceEnrollmentCoordinator {
        try DeviceEnrollmentCoordinator.live(
            configuration: enrollmentConfiguration,
            authorizationConfiguration: deviceAuthorization,
            keychainService: keychainService,
            displayName: displayName,
            platform: UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios",
            model: UIDevice.current.model,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "1.0"
        )
    }

    /// What the owner reads in the portal when deciding whether to approve.
    ///
    /// `UIDevice.current.name` on its own is not enough, and kopilka and
    /// beerCalculator settling for it is a defect rather than a precedent: since
    /// iOS 16 it is the generic model on a real device, so every app on this
    /// phone that enrols separately asks for approval as "iPhone". The whole
    /// point of this screen is approving the *right* one.
    ///
    /// Trimmed and clipped because `DeviceEnrollmentMetadata` rejects an
    /// untrimmed or over-long name outright.
    private static var displayName: String {
        let device = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = device.isEmpty ? "foodtracker" : "foodtracker on \(device)"
        return String(name.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
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

extension Notification.Name {
    /// The server no longer knows this device's key — the token client has
    /// already deleted it, so the only way back is a fresh enrollment. Posted
    /// from a background task, which is why the screen listens for it rather
    /// than being called directly.
    nonisolated static let ftDeviceAuthorizationRevoked = Notification.Name(
        "com.mark1ns0n.foodtracker.device-authorization-revoked"
    )
}
