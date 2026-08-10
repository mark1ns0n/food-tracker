//
//  FTBackfillService.swift
//  foodtracker
//
//  F01.11 — the rows that predate the log are written into it, once.
//

import CoreSync
import Foundation
import SwiftData

/// Writes every row the store already holds into the event log as a `create`,
/// then replays the log back over the tables.
///
/// The whole batch goes down as **one transaction** rather than one append per
/// row with a lookup before it (the card's `contains(id:)` does not exist on the
/// store, and does not need to: an append with a deterministic event id is
/// already idempotent — the store returns the stored event untouched when the
/// content matches, and refuses with `eventIDConflict` when it does not). The
/// transaction matters more than the dedup: a backfill that half-landed and then
/// replayed would rebuild the tables from a log that accounts for only half the
/// rows, and drop the rest — data that at that moment exists nowhere else.
///
/// The closing `replayAll` is not a flourish (F01.09): a legacy `SavedName` row
/// carries a random id while its entity id is derived from the value, so the
/// backfilled entity would otherwise sit in the table *beside* the row it
/// describes. The replay rebuilds the tables from the log and the duplicate is
/// gone.
///
/// The flag is checked first and set last, so every failure mode retries on the
/// next launch: events landed but the replay failed → the re-appended batch is a
/// no-op and the replay runs again.
@MainActor
final class FTBackfillService {
    /// The one-shot flag. `BackupView` reads it too: once the log stands behind
    /// the store, restoring a backup would rewrite the tables behind the log's
    /// back, so import goes away with the same flag.
    static let doneKey = "ft.backfillDone"

    private let modelContext: ModelContext
    private let store: SQLiteEventStore
    private let projector: FTProjector
    private let defaults: UserDefaults

    init(
        modelContext: ModelContext,
        store: SQLiteEventStore,
        projector: FTProjector,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.store = store
        self.projector = projector
        self.defaults = defaults
    }

    var isDone: Bool {
        defaults.bool(forKey: Self.doneKey)
    }

    func runIfNeeded() throws {
        guard !isDone else { return }
        try store.appendLocalEvents(drafts())
        try projector.replayAll()
        defaults.set(true, forKey: Self.doneKey)
    }

    /// One `create` per existing row, each carrying the row whole — the same
    /// drafts the writer emits, so the codecs that read them back are the ones
    /// already under test.
    ///
    /// A row the writer has already materialized (`inLog`, F01.08) gets a second
    /// `create` on its entity: a different event id, so no conflict, and the
    /// same content as the fold it lands on, so no change. Expired delivery and
    /// dine-in rows migrate as they are — expiry is a projection (decision 1),
    /// not a fact about the data.
    private func drafts() throws -> [LocalEventDraft] {
        var drafts = try savedNameDrafts()
        drafts += try modelContext.fetch(FetchDescriptor<Item>()).map { row in
            FTGroceryEvent.createDraft(
                entityID: row.id,
                name: row.name,
                status: row.status,
                type: row.groceryType,
                createdAt: row.createdAt,
                id: FTIDs.backfillEventID(entityID: row.id)
            )
        }
        drafts += try modelContext.fetch(FetchDescriptor<FoodEntry>()).map { row in
            FTDeliveryEvent.createDraft(
                entityID: row.id,
                name: row.name,
                amount: row.amount,
                createdAt: row.createdAt,
                id: FTIDs.backfillEventID(entityID: row.id)
            )
        }
        drafts += try modelContext.fetch(FetchDescriptor<DineInEntry>()).map { row in
            FTDineInEvent.createDraft(
                entityID: row.id,
                name: row.name,
                createdAt: row.createdAt,
                id: FTIDs.backfillEventID(entityID: row.id)
            )
        }
        drafts += try scheduleDrafts()
        drafts += try modelContext.fetch(FetchDescriptor<FastingDebt>()).map { row in
            FTFastingDebtEvent.createDraft(
                entityID: row.id,
                missedMinutes: row.missedMinutes,
                createdAt: row.createdAt,
                id: FTIDs.backfillEventID(entityID: row.id)
            )
        }
        return drafts
    }

    /// The saved names, one event per *entity* rather than per row.
    ///
    /// The entity id is derived from the lower-cased value, so legacy rows that
    /// differ only in case — the old app never collapsed them — are one entity.
    /// Emitting a create per row would make the second one an `eventIDConflict`
    /// when the rows are spelled identically, so the rows are grouped first and
    /// the most recently used spelling speaks for the entity. The event id is
    /// per-device (the U01 pattern): another device backfilling the same name
    /// writes its own event, and LWW resolves the two.
    private func savedNameDrafts() throws -> [LocalEventDraft] {
        let rows = try modelContext.fetch(FetchDescriptor<SavedName>())
        return Dictionary(grouping: rows) { FTIDs.savedName(value: $0.value) }
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { entityID, candidates in
                let winner = candidates.max {
                    ($0.lastUsed, $0.value) < ($1.lastUsed, $1.value)
                }!
                return FTSavedNameEvent.createDraft(
                    entityID: entityID,
                    value: winner.value,
                    lastUsed: winner.lastUsed,
                    id: FTIDs.backfillEventID(
                        deviceID: store.deviceID,
                        name: "ft.savedname." + winner.value.lowercased()
                    )
                )
            }
    }

    /// `entries.first`, the same way the view and the writer read the singleton;
    /// any second row is a leftover the replay removes.
    private func scheduleDrafts() throws -> [LocalEventDraft] {
        guard let row = try modelContext.fetch(FetchDescriptor<FastingEntry>()).first else {
            return []
        }
        return [
            FTFastingScheduleEvent.createDraft(
                startHour: row.startHour,
                startMinute: row.startMinute,
                durationMinutes: row.durationMinutes,
                // The running fast travels with the schedule: a create carries
                // the entity whole (F01.10).
                activeStartDate: row.activeStartDate,
                id: FTIDs.backfillEventID(
                    deviceID: store.deviceID,
                    name: "ft.fasting.schedule"
                )
            )
        ]
    }
}
