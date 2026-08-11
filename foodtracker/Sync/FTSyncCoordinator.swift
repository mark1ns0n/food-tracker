//
//  FTSyncCoordinator.swift
//  foodtracker
//
//  F01.13 — when the log talks to the backend.
//  F01.14 — and what happens to what it says back.
//  F01.15 — plus the push the owner asks for by hand.
//

import AppShell
import CoreSync
import Foundation
import OSLog

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

    /// What the six `ft.*` entity types share. The router groups events by
    /// whatever stands before the first dot, and `RemoteEventProjector` refuses
    /// a prefix that contains one — so this is "ft", not "ft.".
    private static let entityTypePrefix = "ft"

    private let bootstrap: SyncBootstrap
    private let defaults: UserDefaults
    private let registration: Task<Void, Never>
    private var pendingPush: Task<Void, Never>?

    /// The handler is registered with the bootstrap's router here rather than
    /// passed to `SyncBootstrap.live`: the handler needs the event store, and
    /// the store is something the bootstrap opens. Registering afterwards is
    /// what breaks that circle — the alternative is a second connection to the
    /// same database.
    ///
    /// Registration is a `Task` because the router is an actor and this runs
    /// from `foodtrackerApp.init`, which cannot await. Both triggers wait on it
    /// before synchronizing, so a pull can never arrive at a router that has
    /// not been told where `ft.*` goes yet — its events would be counted
    /// unhandled and never projected.
    init(
        bootstrap: SyncBootstrap,
        handler: FTRemoteEventHandler,
        defaults: UserDefaults = .standard
    ) {
        self.bootstrap = bootstrap
        self.defaults = defaults
        registration = Task {
            do {
                try await bootstrap.projectorRouter.register(
                    RemoteEventProjector(entityTypePrefix: Self.entityTypePrefix) { events in
                        await handler.handle(events)
                    }
                )
            } catch {
                Logger.ftSync.error(
                    "Could not register the pull handler: \(String(describing: error))"
                )
            }
        }
    }

    /// The writer appended something. Each append restarts the timer, so the
    /// push goes out once the user pauses rather than once per tap.
    func noteLocalMutation() {
        guard backfillDone else { return }
        pendingPush?.cancel()
        pendingPush = Task { [bootstrap, registration] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await registration.value
            _ = await bootstrap.synchronize(trigger: .localMutation)
        }
    }

    /// The scene came to the foreground, launch included.
    func noteScenePhaseActive() {
        guard backfillDone else { return }
        Task { [bootstrap, registration] in
            await registration.value
            _ = await bootstrap.synchronize(trigger: .foreground)
        }
    }

    /// The owner pressed Synchronize on the sync screen. Same two conditions as
    /// the automatic triggers — the backfill has spoken, and the router knows
    /// where `ft.*` goes — because a manual push is not a different kind of
    /// sync, only a differently timed one.
    ///
    /// `nil` is the gate refusing: there is nothing to report to the owner about
    /// a run that never started. In practice it is unreachable, since the
    /// backfill runs from `ContentView.onAppear` and a failure there is fatal;
    /// it is here so the invariant does not depend on that staying true.
    ///
    /// The trigger value is not read by `SyncBootstrap` at all; `.foreground` is
    /// the closest of the three in meaning — the owner is looking at the screen
    /// and wants both directions to move.
    func synchronizeNow() async -> SyncRunResult? {
        guard backfillDone else { return nil }
        await registration.value
        return await bootstrap.synchronize(trigger: .foreground)
    }

    /// What the sync screen shows about the log. Narrow on purpose: the store
    /// itself already belongs to the writer and the projector, and a third
    /// holder of it would be a third thing that could write.
    var logCounts: FTLogCounts {
        FTLogCounts(
            total: (try? bootstrap.eventStore.eventCount()) ?? 0,
            pending: (try? bootstrap.eventStore.pendingEventCount()) ?? 0
        )
    }

    /// The first sync must come after the backfill (F01 header): a log pushed
    /// before it would hand the backend fresh events with no history behind
    /// them. The flag is read per trigger, not once, so the launch on which the
    /// backfill first runs starts syncing without a restart.
    private var backfillDone: Bool {
        defaults.bool(forKey: FTBackfillService.doneKey)
    }
}

/// How much of the log exists, and how much of it the backend has not seen.
struct FTLogCounts: Equatable {
    var total = 0
    var pending = 0
}

// MARK: - Pull

/// What a page of remote events does to this device.
///
/// Two things, in order: the tables catch up with the log the events have just
/// been merged into, and the fasting reminder is re-planned if the schedule was
/// among them.
///
/// It deliberately knows nothing about `SyncBootstrap` — everything it needs is
/// the log and the projector — so the whole pull path can be exercised over a
/// real store and a stub transport, with no keychain and no network.
@MainActor
final class FTRemoteEventHandler {
    private let eventLog: any FTEventLog
    private let projector: FTProjector
    private let notifications: any FTFastingNotificationScheduling
    private let now: () -> Date

    init(
        eventLog: any FTEventLog,
        projector: FTProjector,
        notifications: any FTFastingNotificationScheduling,
        now: @escaping () -> Date = Date.init
    ) {
        self.eventLog = eventLog
        self.projector = projector
        self.notifications = notifications
        self.now = now
    }

    /// The events are already in the store — `SyncEngine` merges the page before
    /// it hands it over — so this only has to say which entities changed and let
    /// the projector re-read them.
    ///
    /// One entity at a time, each with its own `do`, and that is the point: a
    /// single event this build cannot read (a schema version from a newer
    /// client, an `ft.*` type it has never heard of) would otherwise abort the
    /// page and take every other entity in it down. The cursor has already
    /// moved by then, so those events never come back — the tables would just
    /// stay quietly wrong until the next full replay. Blocked entities keep the
    /// rows they had; everything else in the page still lands.
    func handle(_ events: [SyncEvent]) {
        var scheduleChanged = false

        for (key, batch) in Self.groupedByEntity(events) {
            do {
                try projector.apply(batch)
                if key.entityType == FTEntity.fastingSchedule {
                    scheduleChanged = true
                }
            } catch {
                Logger.ftSync.error(
                    """
                    Could not project \(key.entityType, privacy: .public) \
                    \(key.entityID.uuidString, privacy: .public): \
                    \(String(describing: error))
                    """
                )
            }
        }

        guard scheduleChanged else { return }
        rescheduleFastingNotification()
    }

    /// The schedule the user is now on may have been set, started, stopped or
    /// thrown away on the other device, and each of those implies a different
    /// pending reminder — so the plan is derived from the state the pull left
    /// behind rather than from the operation that arrived.
    ///
    /// Both devices end up notifying about the same fast. That is accepted
    /// (F01.14): the alternative is a reminder that only reaches whichever
    /// device the user was holding when they pressed Start.
    private func rescheduleFastingNotification() {
        let entityID = FTIDs.fastingSchedule()
        do {
            let schedule = try FTFastingScheduleProjection.project(
                eventLog.projection(
                    entityType: FTEntity.fastingSchedule,
                    entityID: entityID,
                    supportedSchemaVersion: FTEntity.schemaVersion
                ),
                entityID: entityID
            )
            notifications.apply(FTFastingNotificationPlan(schedule: schedule, now: now()))
        } catch {
            // The tables were updated regardless; leaving the pending reminder
            // as it was beats cancelling one on the strength of a schedule that
            // could not be read.
            Logger.ftSync.error(
                "Could not re-plan the fasting reminder: \(String(describing: error))"
            )
        }
    }

    /// Grouped, but in the order the entities first appear in the page, so a
    /// failure log reads in the order the server sent things.
    private static func groupedByEntity(_ events: [SyncEvent]) -> [(FTRemoteEntityKey, [SyncEvent])] {
        var batches: [FTRemoteEntityKey: [SyncEvent]] = [:]
        var order: [FTRemoteEntityKey] = []
        for event in events {
            let key = FTRemoteEntityKey(entityType: event.entityType, entityID: event.entityID)
            if batches[key] == nil {
                order.append(key)
            }
            batches[key, default: []].append(event)
        }
        return order.map { ($0, batches[$0] ?? []) }
    }
}

private struct FTRemoteEntityKey: Hashable {
    let entityType: String
    let entityID: UUID
}

extension Logger {
    static let ftSync = Logger(
        subsystem: FTSyncComposition.applicationIdentifier,
        category: "Sync"
    )
}
