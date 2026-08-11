//
//  FTSyncController.swift
//  foodtracker
//
//  F01.15 — enrol this device, so there can be a second one.
//

import AppShell
import Combine
import CoreSync
import Foundation

/// State behind the sync screen: whether this device is allowed to talk to the
/// backend, and what the log looks like from here.
///
/// Unlike the same controller in kopilka and beerCalculator, this one does not
/// build a `SyncBootstrap`. `foodtrackerApp` already opened one, and the store
/// inside it is the store the writer and the projector hold — a second bootstrap
/// would be a second SQLite connection to the same database, racing on the HLC
/// metadata. So the screen borrows the coordinator instead of composing its own
/// stack.
///
/// There is no backfill button here either, for the same reason there is no
/// backfill decision left to make: `FTBackfillService.runIfNeeded()` runs at
/// launch and a failure there is fatal (F01.11). The screen reports the flag; it
/// does not offer to flip it.
@MainActor
final class FTSyncController: ObservableObject {
    @Published private(set) var enrollment: DeviceEnrollmentState = .notEnrolled
    @Published private(set) var counts = FTLogCounts()
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncMessage: String?
    @Published var enrollmentLink = ""

    /// Where the owner goes to mint the link that is pasted below it.
    let portalURL = FTSyncComposition.enrollmentConfiguration.newDevicePortalURL

    private let coordinator: FTSyncCoordinator?
    private var enrollmentTask: Task<Void, Never>?

    /// `nil` when the sync stack could not be composed — the app still works,
    /// entirely offline, and the screen says so.
    init(coordinator: FTSyncCoordinator?) {
        self.coordinator = coordinator
        refresh()
    }

    var isAvailable: Bool { coordinator != nil }

    var isEnrolled: Bool { enrollment == .enrolled }

    func refresh() {
        refreshEnrollment()
        refreshCounts()
    }

    // MARK: - Enrollment

    /// Reads the enrollment back out of the keychain. `.binding` means a
    /// previous run was cut off between the owner's approval and the key being
    /// bound, so it is resumed rather than restarted — restarting would ask the
    /// owner to approve a device the server already approved.
    private func refreshEnrollment() {
        guard enrollmentTask == nil else { return }
        do {
            let coordinator = try FTSyncComposition.makeEnrollmentCoordinator()
            enrollment = coordinator.initialState()
            guard enrollment == .binding else { return }
            enrollmentTask = Task { [weak self] in
                await coordinator.resumeBinding { [weak self] state in
                    self?.enrollment = state
                }
                self?.enrollmentTask = nil
            }
        } catch {
            enrollment = .refreshError(.keyOrStorage)
        }
    }

    /// Takes the enrollment link the owner pasted from the devices portal. The
    /// link carries a one-time bootstrap secret, so it is cleared immediately
    /// and never logged or shown back — only its outcome is.
    func enroll() {
        let trimmed = enrollmentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            enrollment = .refreshError(.invalidLink)
            return
        }
        enrollmentLink = ""
        enrollmentTask?.cancel()
        do {
            let coordinator = try FTSyncComposition.makeEnrollmentCoordinator()
            enrollmentTask = Task { [weak self] in
                await coordinator.enroll(from: url) { [weak self] state in
                    self?.enrollment = state
                }
                self?.enrollmentTask = nil
            }
        } catch {
            enrollment = .refreshError(.keyOrStorage)
            enrollmentTask = nil
        }
    }

    /// The device key was rejected and deleted underneath us. Any enrollment
    /// still in flight is chasing a key that no longer exists.
    func markRevoked() {
        enrollmentTask?.cancel()
        enrollmentTask = nil
        enrollment = .revoked
    }

    // MARK: - Sync

    func synchronize() {
        guard let coordinator, !isSyncing else { return }
        isSyncing = true
        Task { [weak self] in
            let result = await coordinator.synchronizeNow()
            self?.isSyncing = false
            self?.lastSyncMessage = Self.describe(result)
            self?.refreshCounts()
        }
    }

    func refreshCounts() {
        counts = coordinator?.logCounts ?? FTLogCounts()
    }

    private static func describe(_ result: SyncRunResult?) -> String {
        switch result {
        case let .synchronized(summary):
            "Sent \(summary.submittedEventCount), received \(summary.receivedEventCount)"
        case .skippedNoCredential:
            "This device is not connected"
        case .failed:
            "Sync did not go through"
        case nil:
            "Waiting for the first import to finish"
        }
    }
}
