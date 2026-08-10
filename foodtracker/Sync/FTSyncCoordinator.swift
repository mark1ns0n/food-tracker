//
//  FTSyncCoordinator.swift
//  foodtracker
//
//  F01.13 — when the log talks to the backend.
//

import AppShell
import Foundation

/// Decides *when* to synchronize; `SyncBootstrap` owns how, and whether it may
/// at all — an unenrolled device comes back as `.skippedNoCredential`, which is
/// the "no token → silently do nothing" of the card.
///
/// Two triggers only: a short debounce after a local append, so a burst of
/// toggles travels as one push, and the scene becoming active — which on iOS
/// also covers launch. No BGTaskScheduler: this app is on its way out, and a
/// device nobody is looking at can catch up the next time somebody does.
@MainActor
final class FTSyncCoordinator {
    static let debounce: Duration = .seconds(2)

    private let bootstrap: SyncBootstrap
    private let defaults: UserDefaults
    private var pendingPush: Task<Void, Never>?

    init(bootstrap: SyncBootstrap, defaults: UserDefaults = .standard) {
        self.bootstrap = bootstrap
        self.defaults = defaults
    }

    /// The writer appended something. Each append restarts the timer, so the
    /// push goes out once the user pauses rather than once per tap.
    func noteLocalMutation() {
        guard backfillDone else { return }
        pendingPush?.cancel()
        pendingPush = Task { [bootstrap] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            _ = await bootstrap.synchronize(trigger: .localMutation)
        }
    }

    /// The scene came to the foreground, launch included.
    func noteScenePhaseActive() {
        guard backfillDone else { return }
        Task { [bootstrap] in
            _ = await bootstrap.synchronize(trigger: .foreground)
        }
    }

    /// The first sync must come after the backfill (F01 header): a log pushed
    /// before it would hand the backend fresh events with no history behind
    /// them. The flag is read per trigger, not once, so the launch on which the
    /// backfill first runs starts syncing without a restart.
    private var backfillDone: Bool {
        defaults.bool(forKey: FTBackfillService.doneKey)
    }
}
