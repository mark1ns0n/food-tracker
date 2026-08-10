//
//  FTWriter.swift
//  foodtracker
//
//  F01.08 — the only way a mutation reaches the tables.
//

import CoreSync
import Foundation
import SwiftData

// MARK: - Drafts

/// The `ft.Grocery` drafts, kept next to the writer that assembles them (the
/// `BanEntrySync.createDraft` shape).
///
/// `createDraft` takes an explicit event id because the backfill of F01.11 needs
/// a deterministic one — re-running the migration then writes the same event and
/// the store rejects it as a duplicate. A live mutation leaves it `nil` and lets
/// the store mint one.
enum FTGroceryEvent {
    static func createDraft(
        entityID: UUID,
        name: String,
        status: ItemStatus,
        type: GroceryType,
        createdAt: Date,
        id: UUID? = nil
    ) -> LocalEventDraft {
        LocalEventDraft(
            id: id,
            schemaVersion: FTEntity.schemaVersion,
            entityType: FTEntity.grocery,
            entityID: entityID,
            operation: .create,
            payload: FTGroceryPayload(
                name: name,
                status: status,
                type: type,
                createdAt: createdAt
            ).value
        )
    }

    /// Only the changed fields travel: a toggle carries a status and nothing
    /// else, so it cannot undo an edit that reached the log from elsewhere in
    /// between.
    static func updateDraft(entityID: UUID, _ payload: FTGroceryPayload) -> LocalEventDraft {
        LocalEventDraft(
            schemaVersion: FTEntity.schemaVersion,
            entityType: FTEntity.grocery,
            entityID: entityID,
            operation: .update,
            payload: payload.value
        )
    }

    static func deleteDraft(entityID: UUID) -> LocalEventDraft {
        LocalEventDraft(
            schemaVersion: FTEntity.schemaVersion,
            entityType: FTEntity.grocery,
            entityID: entityID,
            operation: .delete,
            payload: .object([:])
        )
    }
}

/// A delivery entry is only ever created: the UI has no edit, and expiry hides
/// a row instead of deleting it (decision 1 of F01), so there is no `update` or
/// `delete` draft to write.
enum FTDeliveryEvent {
    static func createDraft(
        entityID: UUID,
        name: String,
        amount: Double,
        createdAt: Date,
        id: UUID? = nil
    ) -> LocalEventDraft {
        LocalEventDraft(
            id: id,
            schemaVersion: FTEntity.schemaVersion,
            entityType: FTEntity.delivery,
            entityID: entityID,
            operation: .create,
            payload: FTDeliveryPayload(name: name, amount: amount, createdAt: createdAt).value
        )
    }
}

/// Create-only for the same reasons as `FTDeliveryEvent`.
enum FTDineInEvent {
    static func createDraft(
        entityID: UUID,
        name: String,
        createdAt: Date,
        id: UUID? = nil
    ) -> LocalEventDraft {
        LocalEventDraft(
            id: id,
            schemaVersion: FTEntity.schemaVersion,
            entityType: FTEntity.dineIn,
            entityID: entityID,
            operation: .create,
            payload: FTDineInPayload(name: name, createdAt: createdAt).value
        )
    }
}

/// The entity id comes from the name itself (F01.06), so a `create` from a
/// second device is an upsert of the same entity rather than a duplicate.
enum FTSavedNameEvent {
    static func createDraft(
        entityID: UUID,
        value: String,
        lastUsed: Date,
        id: UUID? = nil
    ) -> LocalEventDraft {
        LocalEventDraft(
            id: id,
            schemaVersion: FTEntity.schemaVersion,
            entityType: FTEntity.savedName,
            entityID: entityID,
            operation: .create,
            payload: FTSavedNamePayload(value: value, lastUsed: lastUsed).jsonValue
        )
    }

    /// Reuse carries the date only, so the spelling stays as it was first
    /// typed — the suggestion list is not rewritten by someone typing the same
    /// restaurant in lower case.
    static func updateDraft(entityID: UUID, lastUsed: Date) -> LocalEventDraft {
        LocalEventDraft(
            schemaVersion: FTEntity.schemaVersion,
            entityType: FTEntity.savedName,
            entityID: entityID,
            operation: .update,
            payload: FTSavedNamePayload(lastUsed: lastUsed).jsonValue
        )
    }
}

// MARK: - The writer

/// Every user mutation, as an event first.
///
/// The writer never assigns a field on a model. It appends to the log and then
/// asks the projector to re-read what it just wrote, so the row the user sees is
/// the row a replay would rebuild — there is no second code path that could
/// produce a state the events do not describe.
///
/// It runs the cascades of decision 2 (the auto-reset, and in F01.09 the
/// zero-amount delivery behind a dine-in) because it is the device where the
/// user acted; the projector runs none of them, so a device that merely receives
/// the events does not generate its own copy.
@MainActor
final class FTWriter {
    private let modelContext: ModelContext
    private let store: SQLiteEventStore
    private let projector: FTProjector

    init(modelContext: ModelContext, store: SQLiteEventStore, projector: FTProjector) {
        self.modelContext = modelContext
        self.store = store
        self.projector = projector
    }

    // MARK: Groceries

    @discardableResult
    func addGrocery(name: String, type: GroceryType, createdAt: Date = Date()) throws -> UUID {
        let entityID = UUID()
        try write([
            FTGroceryEvent.createDraft(
                entityID: entityID,
                name: name,
                status: .available,
                type: type,
                createdAt: createdAt
            )
        ])
        return entityID
    }

    func editGrocery(id: UUID, name: String, type: GroceryType) throws {
        try inLog(id)
        try write([FTGroceryEvent.updateDraft(entityID: id, FTGroceryPayload(name: name, type: type))])
    }

    /// The status flips against the log, not against the row on screen: the log
    /// is what the next replay reads, and the row is only its cache.
    func toggleGrocery(id: UUID) throws {
        let current = try inLog(id)
        let flipped: ItemStatus = current.status == .available ? .used : .available
        try write([FTGroceryEvent.updateDraft(entityID: id, FTGroceryPayload(status: flipped))])
    }

    func deleteGrocery(id: UUID) throws {
        try inLog(id)
        try write([FTGroceryEvent.deleteDraft(entityID: id)])
    }

    /// The auto-reset and the manual refresh, as one update per grocery.
    ///
    /// The view decides *which* ids are due a reset — it is the one that knows a
    /// type has gone fully used — and the writer only records the decision. The
    /// whole batch is one transaction: a half-reset type would show up on the
    /// other device as a list nobody meant to leave that way.
    func resetGroceries(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            try inLog(id)
        }
        try write(ids.map {
            FTGroceryEvent.updateDraft(entityID: $0, FTGroceryPayload(status: .available))
        })
    }

    // MARK: Delivery, dine-in, and the names behind them

    /// An order also remembers who it was from, so the two events go down
    /// together: a delivery whose name never made it into the suggestions would
    /// leave the user retyping it on the next device.
    @discardableResult
    func addDelivery(name: String, amount: Double, createdAt: Date = Date()) throws -> UUID {
        let entityID = UUID()
        try write(
            [
                FTDeliveryEvent.createDraft(
                    entityID: entityID,
                    name: name,
                    amount: amount,
                    createdAt: createdAt
                )
            ] + savedNameDrafts(value: name, lastUsed: createdAt)
        )
        return entityID
    }

    /// Eating in also puts the restaurant in the delivery list at zero, which is
    /// what stops an order from there for the next thirty days.
    ///
    /// The cascade runs here, on the device where the user acted (decision 2),
    /// and travels as ordinary events; the projector runs no cascades, so the
    /// other device receives this one zero-amount entry rather than inventing
    /// its own.
    @discardableResult
    func addDineIn(name: String, createdAt: Date = Date()) throws -> UUID {
        let entityID = UUID()
        var drafts = [FTDineInEvent.createDraft(entityID: entityID, name: name, createdAt: createdAt)]
        if try !hasActiveDelivery(named: name) {
            drafts.append(
                FTDeliveryEvent.createDraft(
                    entityID: UUID(),
                    name: name,
                    amount: 0,
                    createdAt: createdAt
                )
            )
        }
        drafts += try savedNameDrafts(value: name, lastUsed: createdAt)
        try write(drafts)
        return entityID
    }

    /// The "+" in the dialogs: remember this name without ordering anything.
    func upsertSavedName(value: String, lastUsed: Date = Date()) throws {
        try write(savedNameDrafts(value: value, lastUsed: lastUsed))
    }

    /// `create` for a name the log has never held, `update {lastUsed}` for one
    /// it has. Both address the same entity id, derived from the lower-cased
    /// name, so "Talabat" and "talabat" are one suggestion and not two.
    private func savedNameDrafts(value: String, lastUsed: Date) throws -> [LocalEventDraft] {
        let entityID = FTIDs.savedName(value: value)
        let known = try FTSavedNameProjection.project(
            store.projection(
                entityType: FTEntity.savedName,
                entityID: entityID,
                supportedSchemaVersion: FTEntity.schemaVersion
            ),
            entityID: entityID
        ) != nil
        return [
            known
                ? FTSavedNameEvent.updateDraft(entityID: entityID, lastUsed: lastUsed)
                : FTSavedNameEvent.createDraft(entityID: entityID, value: value, lastUsed: lastUsed)
        ]
    }

    /// Whether the user already has a delivery entry for this restaurant that
    /// has not expired.
    ///
    /// Asked of the table rather than of the log, and deliberately: the question
    /// is what the user is looking at, and until the backfill of F01.11 the
    /// table also holds rows written before the log existed. Expiry stays a
    /// projection over `createdAt` on the model (decision 1), so there is one
    /// definition of "active" rather than a second one here.
    private func hasActiveDelivery(named name: String) throws -> Bool {
        let normalized = name.lowercased()
        return try modelContext.fetch(FetchDescriptor<FoodEntry>())
            .contains { !$0.isExpired && $0.name.lowercased() == normalized }
    }

    // MARK: Writing

    @discardableResult
    private func write(_ drafts: [LocalEventDraft]) throws -> [SyncEvent] {
        let events = try store.appendLocalEvents(drafts)
        try projector.apply(events)
        return events
    }

    /// Makes sure the log already knows the grocery a mutation is about, so that
    /// an `update` never lands on an entity the fold projects as `nil` — which
    /// the projector would resolve by deleting the row.
    ///
    /// It matters between here and F01.11: the rows already in the store were
    /// written before any of this existed and no event accounts for them, so the
    /// first toggle of a grocery the user has had for months would otherwise
    /// erase it. A row the log has never heard of is written into it whole, from
    /// what the row currently holds — the same `create` the backfill would emit,
    /// just earlier. Once the backfill has run this path is unreachable.
    @discardableResult
    private func inLog(_ id: UUID) throws -> FTGroceryProjection {
        let slice = try store.projection(
            entityType: FTEntity.grocery,
            entityID: id,
            supportedSchemaVersion: FTEntity.schemaVersion
        )
        if let projection = try FTGroceryProjection.project(slice, entityID: id) {
            return projection
        }
        // The log has the entity and says it is gone: a mutation now would
        // resurrect a grocery the user deleted, so it is refused rather than
        // quietly turned into a `create`.
        guard slice.events.isEmpty else {
            throw FTWriterError.deletedGrocery(id)
        }
        guard let row = try modelContext.fetch(FetchDescriptor<Item>()).first(where: { $0.id == id })
        else {
            throw FTWriterError.unknownGrocery(id)
        }

        try write([
            FTGroceryEvent.createDraft(
                entityID: id,
                name: row.name,
                status: row.status,
                type: row.groceryType,
                createdAt: row.createdAt
            )
        ])

        guard let projection = try FTGroceryProjection.project(
            try store.projection(
                entityType: FTEntity.grocery,
                entityID: id,
                supportedSchemaVersion: FTEntity.schemaVersion
            ),
            entityID: id
        ) else {
            throw FTWriterError.unknownGrocery(id)
        }
        return projection
    }
}

enum FTWriterError: Error, Equatable {
    /// Neither the log nor the table has ever held this grocery.
    case unknownGrocery(UUID)
    /// The log holds it and says it was deleted.
    case deletedGrocery(UUID)
}
