//
//  FTProjector.swift
//  foodtracker
//
//  F01.07 — the log is the truth, SwiftData is its cache.
//

import CoreSync
import Foundation
import SwiftData

// MARK: - The read port

/// The half of the event store a projector needs.
///
/// A protocol rather than `SQLiteEventStore` itself for one reason: the store
/// stamps its own device onto everything it appends, so through it a test can
/// only ever produce a single-device log. Last-writer-wins between two devices,
/// resurrection and out-of-order arrival are exactly the rules that need a
/// fixture log to be checked at all.
protocol FTEventLog {
    func projection(
        entityType: String,
        entityID: UUID,
        supportedSchemaVersion: Int
    ) throws -> ProjectionSlice

    func projections(
        entityType: String,
        supportedSchemaVersion: Int
    ) throws -> [EntityProjectionSlice]
}

extension SQLiteEventStore: FTEventLog {}

// MARK: - Projections

/// One projection = the state of one entity after its whole slice of the log
/// has been folded. Plain values, so the fold can be tested without SwiftData.
struct FTGroceryProjection: Equatable {
    var entityID: UUID
    var name: String
    var status: ItemStatus
    var type: GroceryType
    var createdAt: Date
}

struct FTDeliveryProjection: Equatable {
    var entityID: UUID
    var name: String
    var amount: Double
    var createdAt: Date
}

struct FTDineInProjection: Equatable {
    var entityID: UUID
    var name: String
    var createdAt: Date
}

struct FTSavedNameProjection: Equatable {
    var entityID: UUID
    var value: String
    var lastUsed: Date
}

struct FTFastingScheduleProjection: Equatable {
    var entityID: UUID
    var startHour: Int
    var startMinute: Int
    var durationMinutes: Int
    var activeStartDate: Date?
    var createdAt: Date
}

struct FTFastingDebtProjection: Equatable {
    var entityID: UUID
    var missedMinutes: Int
    var createdAt: Date
}

// MARK: - The fold

/// Folding an entity's whole slice, rather than applying deltas to whatever the
/// table happens to hold, is what makes the rules below fall out for free:
///
/// - **order does not matter** — the slice is sorted here, so a batch that
///   arrived shuffled projects to the same state as one that arrived in order;
/// - **there are no tombstones to remember** — the `delete` event *is* the
///   tombstone, and it is in the slice forever. An `update` after it lands on a
///   `nil` projection and is dropped; a `create` after it starts a new one
///   (resurrection, B01);
/// - **it survives a restart** — nothing depends on state the projector was
///   holding in memory when the batch before this one arrived.
enum FTFold {
    static func project<Projection>(
        _ slice: ProjectionSlice,
        entityType: String,
        entityID: UUID,
        create: (SyncEvent) throws -> Projection,
        update: (SyncEvent, inout Projection) -> Void
    ) throws -> Projection? {
        guard !slice.requiresUpgrade else {
            throw FTProjectionError.requiresUpgrade(entityType, entityID)
        }

        var projection: Projection?
        for event in slice.events.sorted(by: order) {
            guard event.entityType == entityType, event.entityID == entityID else {
                throw FTProjectionError.foreignEvent(event.id)
            }
            guard event.schemaVersion <= FTEntity.schemaVersion else {
                throw FTProjectionError.requiresUpgrade(entityType, entityID)
            }

            switch event.operation {
            case .create:
                // Every `create` this app writes carries the entity whole, so a
                // second one (a saved name upserted from another device, both
                // devices backfilling the schedule) replaces rather than merges.
                projection = try create(event)
            case .update:
                guard var current = projection else { continue }
                update(event, &current)
                projection = current
            case .delete:
                projection = nil
            }
        }
        return projection
    }

    /// HLC first, event id to break a tie — the same order the store reads in,
    /// so a slice from the store and a slice from a fixture fold identically.
    static func order(_ lhs: SyncEvent, _ rhs: SyncEvent) -> Bool {
        if lhs.hlc != rhs.hlc {
            return lhs.hlc < rhs.hlc
        }
        return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }
}

extension FTGroceryProjection {
    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTGroceryProjection? {
        try FTFold.project(slice, entityType: FTEntity.grocery, entityID: entityID) { event in
            let payload = FTGroceryPayload.decode(event.payload)
            guard let name = payload.name,
                  let status = payload.status,
                  let type = payload.type,
                  let createdAt = payload.createdAt
            else {
                throw FTProjectionError.incompleteCreate(event.id)
            }
            return FTGroceryProjection(
                entityID: entityID,
                name: name,
                status: status,
                type: type,
                createdAt: createdAt
            )
        } update: { event, projection in
            let payload = FTGroceryPayload.decode(event.payload)
            if let name = payload.name { projection.name = name }
            if let status = payload.status { projection.status = status }
            if let type = payload.type { projection.type = type }
            if let createdAt = payload.createdAt { projection.createdAt = createdAt }
        }
    }
}

extension FTDeliveryProjection {
    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTDeliveryProjection? {
        try FTFold.project(slice, entityType: FTEntity.delivery, entityID: entityID) { event in
            let payload = FTDeliveryPayload.decode(event.payload)
            guard let name = payload.name,
                  let amount = payload.amount,
                  let createdAt = payload.createdAt
            else {
                throw FTProjectionError.incompleteCreate(event.id)
            }
            return FTDeliveryProjection(
                entityID: entityID,
                name: name,
                amount: amount,
                createdAt: createdAt
            )
        } update: { event, projection in
            let payload = FTDeliveryPayload.decode(event.payload)
            if let name = payload.name { projection.name = name }
            if let amount = payload.amount { projection.amount = amount }
            if let createdAt = payload.createdAt { projection.createdAt = createdAt }
        }
    }
}

extension FTDineInProjection {
    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTDineInProjection? {
        try FTFold.project(slice, entityType: FTEntity.dineIn, entityID: entityID) { event in
            let payload = FTDineInPayload.decode(event.payload)
            guard let name = payload.name, let createdAt = payload.createdAt else {
                throw FTProjectionError.incompleteCreate(event.id)
            }
            return FTDineInProjection(entityID: entityID, name: name, createdAt: createdAt)
        } update: { event, projection in
            let payload = FTDineInPayload.decode(event.payload)
            if let name = payload.name { projection.name = name }
            if let createdAt = payload.createdAt { projection.createdAt = createdAt }
        }
    }
}

extension FTSavedNameProjection {
    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTSavedNameProjection? {
        try FTFold.project(slice, entityType: FTEntity.savedName, entityID: entityID) { event in
            let payload = FTSavedNamePayload.decode(event.payload)
            guard let value = payload.value, let lastUsed = payload.lastUsed else {
                throw FTProjectionError.incompleteCreate(event.id)
            }
            return FTSavedNameProjection(entityID: entityID, value: value, lastUsed: lastUsed)
        } update: { event, projection in
            let payload = FTSavedNamePayload.decode(event.payload)
            if let value = payload.value { projection.value = value }
            if let lastUsed = payload.lastUsed { projection.lastUsed = lastUsed }
        }
    }
}

extension FTFastingScheduleProjection {
    static func project(
        _ slice: ProjectionSlice,
        entityID: UUID
    ) throws -> FTFastingScheduleProjection? {
        try FTFold.project(slice, entityType: FTEntity.fastingSchedule, entityID: entityID) { event in
            let payload = FTFastingSchedulePayload.decode(event.payload)
            guard let startHour = payload.startHour,
                  let startMinute = payload.startMinute,
                  let durationMinutes = payload.durationMinutes
            else {
                throw FTProjectionError.incompleteCreate(event.id)
            }
            return FTFastingScheduleProjection(
                entityID: entityID,
                startHour: startHour,
                startMinute: startMinute,
                durationMinutes: durationMinutes,
                // The schedule's payload has no `createdAt` of its own (it is a
                // singleton, not a dated row), so the event's own timestamp
                // stands in — a value every device replays the same way.
                activeStartDate: payload.activeStartDate ?? nil,
                createdAt: event.createdAt
            )
        } update: { event, projection in
            let payload = FTFastingSchedulePayload.decode(event.payload)
            if let startHour = payload.startHour { projection.startHour = startHour }
            if let startMinute = payload.startMinute { projection.startMinute = startMinute }
            if let durationMinutes = payload.durationMinutes {
                projection.durationMinutes = durationMinutes
            }
            // Outer optional present = the event mentioned the field, so apply
            // it even when the inner value is nil: that null is "stop the fast".
            if let activeStartDate = payload.activeStartDate {
                projection.activeStartDate = activeStartDate
            }
        }
    }
}

extension FTFastingDebtProjection {
    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTFastingDebtProjection? {
        try FTFold.project(slice, entityType: FTEntity.fastingDebt, entityID: entityID) { event in
            let payload = FTFastingDebtPayload.decode(event.payload)
            guard let missedMinutes = payload.missedMinutes, let createdAt = payload.createdAt else {
                throw FTProjectionError.incompleteCreate(event.id)
            }
            return FTFastingDebtProjection(
                entityID: entityID,
                missedMinutes: missedMinutes,
                createdAt: createdAt
            )
        } update: { event, projection in
            let payload = FTFastingDebtPayload.decode(event.payload)
            if let missedMinutes = payload.missedMinutes { projection.missedMinutes = missedMinutes }
            if let createdAt = payload.createdAt { projection.createdAt = createdAt }
        }
    }
}

// MARK: - Models as projection targets

/// What a SwiftData model has to say about itself for the projector to keep one
/// table in step with one `ft.*` entity type.
protocol FTProjectable: PersistentModel {
    associatedtype Projection

    static var ftEntityType: String { get }
    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> Projection?
    static func make(_ projection: Projection) -> Self

    var ftEntityID: UUID { get }
    func apply(_ projection: Projection)
}

extension Item: FTProjectable {
    static let ftEntityType = FTEntity.grocery
    var ftEntityID: UUID { id }

    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTGroceryProjection? {
        try FTGroceryProjection.project(slice, entityID: entityID)
    }

    /// The initializer only brings a row into being; `apply` is the single place
    /// that fills it, so a rebuilt row and an updated one cannot drift apart.
    static func make(_ projection: FTGroceryProjection) -> Item {
        let item = Item(
            name: projection.name,
            status: projection.status,
            type: projection.type,
            id: projection.entityID
        )
        item.apply(projection)
        return item
    }

    func apply(_ projection: FTGroceryProjection) {
        name = projection.name
        status = projection.status
        type = projection.type
        createdAt = projection.createdAt
    }
}

extension FoodEntry: FTProjectable {
    static let ftEntityType = FTEntity.delivery
    var ftEntityID: UUID { id }

    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTDeliveryProjection? {
        try FTDeliveryProjection.project(slice, entityID: entityID)
    }

    static func make(_ projection: FTDeliveryProjection) -> FoodEntry {
        let entry = FoodEntry(
            name: projection.name,
            amount: projection.amount,
            createdAt: projection.createdAt,
            id: projection.entityID
        )
        entry.apply(projection)
        return entry
    }

    func apply(_ projection: FTDeliveryProjection) {
        name = projection.name
        amount = projection.amount
        createdAt = projection.createdAt
    }
}

extension DineInEntry: FTProjectable {
    static let ftEntityType = FTEntity.dineIn
    var ftEntityID: UUID { id }

    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTDineInProjection? {
        try FTDineInProjection.project(slice, entityID: entityID)
    }

    static func make(_ projection: FTDineInProjection) -> DineInEntry {
        let entry = DineInEntry(
            name: projection.name,
            createdAt: projection.createdAt,
            id: projection.entityID
        )
        entry.apply(projection)
        return entry
    }

    func apply(_ projection: FTDineInProjection) {
        name = projection.name
        createdAt = projection.createdAt
    }
}

extension SavedName: FTProjectable {
    static let ftEntityType = FTEntity.savedName
    var ftEntityID: UUID { id }

    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTSavedNameProjection? {
        try FTSavedNameProjection.project(slice, entityID: entityID)
    }

    static func make(_ projection: FTSavedNameProjection) -> SavedName {
        let name = SavedName(
            value: projection.value,
            lastUsed: projection.lastUsed,
            id: projection.entityID
        )
        name.apply(projection)
        return name
    }

    func apply(_ projection: FTSavedNameProjection) {
        value = projection.value
        lastUsed = projection.lastUsed
    }
}

extension FastingEntry: FTProjectable {
    static let ftEntityType = FTEntity.fastingSchedule

    /// The one `ftEntityID` that is not the row's own id: the schedule is a
    /// singleton, and F01.06 gave it a fixed entity id rather than a row id.
    ///
    /// So every row in this table *is* that one entity, whatever id it was
    /// stored under — which is what lets the projector adopt the schedule the
    /// user set up before the log existed, instead of leaving it beside a second
    /// row and making `entries.first` a coin toss.
    var ftEntityID: UUID { FTIDs.fastingSchedule() }

    static func project(
        _ slice: ProjectionSlice,
        entityID: UUID
    ) throws -> FTFastingScheduleProjection? {
        try FTFastingScheduleProjection.project(slice, entityID: entityID)
    }

    static func make(_ projection: FTFastingScheduleProjection) -> FastingEntry {
        let entry = FastingEntry(
            startHour: projection.startHour,
            startMinute: projection.startMinute,
            durationMinutes: projection.durationMinutes,
            createdAt: projection.createdAt,
            id: projection.entityID
        )
        entry.apply(projection)
        return entry
    }

    func apply(_ projection: FTFastingScheduleProjection) {
        startHour = projection.startHour
        startMinute = projection.startMinute
        durationMinutes = projection.durationMinutes
        activeStartDate = projection.activeStartDate
        createdAt = projection.createdAt
    }
}

extension FastingDebt: FTProjectable {
    static let ftEntityType = FTEntity.fastingDebt
    var ftEntityID: UUID { id }

    static func project(_ slice: ProjectionSlice, entityID: UUID) throws -> FTFastingDebtProjection? {
        try FTFastingDebtProjection.project(slice, entityID: entityID)
    }

    static func make(_ projection: FTFastingDebtProjection) -> FastingDebt {
        let debt = FastingDebt(
            missedMinutes: projection.missedMinutes,
            createdAt: projection.createdAt,
            id: projection.entityID
        )
        debt.apply(projection)
        return debt
    }

    func apply(_ projection: FTFastingDebtProjection) {
        missedMinutes = projection.missedMinutes
        createdAt = projection.createdAt
    }
}

// MARK: - The projector

/// Replays `ft.*` events into the six SwiftData tables.
///
/// It runs no cascades and schedules no notifications. Both belong to the device
/// where the user acted, and travel as ordinary events (decision 2 of F01):
/// a projector that re-ran them would give every device its own copy.
@MainActor
final class FTProjector {
    private let eventLog: any FTEventLog
    private let modelContext: ModelContext

    init(eventLog: any FTEventLog, modelContext: ModelContext) {
        self.eventLog = eventLog
        self.modelContext = modelContext
    }

    /// Rebuild all six tables from the whole log. Rows the log does not account
    /// for are dropped — after a replay the tables hold what the events say and
    /// nothing else.
    func replayAll() throws {
        try rebuild(Item.self)
        try rebuild(FoodEntry.self)
        try rebuild(DineInEntry.self)
        try rebuild(SavedName.self)
        try rebuild(FastingEntry.self)
        try rebuild(FastingDebt.self)
        try saveIfNeeded()
    }

    /// Re-project just the entities this batch names — for a local mutation the
    /// writer has just appended, or a page of remote events that has just been
    /// merged.
    ///
    /// The events have to be in the log already: the batch says *what changed*,
    /// while the state still comes from folding each entity's whole slice.
    func apply(_ events: [SyncEvent]) throws {
        var eventIDsByEntity: [FTEntityKey: [UUID]] = [:]
        var order: [FTEntityKey] = []
        for event in events {
            let key = FTEntityKey(entityType: event.entityType, entityID: event.entityID)
            if eventIDsByEntity[key] == nil {
                order.append(key)
            }
            eventIDsByEntity[key, default: []].append(event.id)
        }

        for key in order {
            let eventIDs = eventIDsByEntity[key] ?? []
            switch key.entityType {
            case FTEntity.grocery:
                try replace(Item.self, entityID: key.entityID, expecting: eventIDs)
            case FTEntity.delivery:
                try replace(FoodEntry.self, entityID: key.entityID, expecting: eventIDs)
            case FTEntity.dineIn:
                try replace(DineInEntry.self, entityID: key.entityID, expecting: eventIDs)
            case FTEntity.savedName:
                try replace(SavedName.self, entityID: key.entityID, expecting: eventIDs)
            case FTEntity.fastingSchedule:
                try replace(FastingEntry.self, entityID: key.entityID, expecting: eventIDs)
            case FTEntity.fastingDebt:
                try replace(FastingDebt.self, entityID: key.entityID, expecting: eventIDs)
            default:
                throw FTProjectorError.unexpectedEntityType(key.entityType)
            }
        }
        try saveIfNeeded()
    }

    private func rebuild<Model: FTProjectable>(_ type: Model.Type) throws {
        let slices = try eventLog.projections(
            entityType: Model.ftEntityType,
            supportedSchemaVersion: FTEntity.schemaVersion
        )
        for row in try modelContext.fetch(FetchDescriptor<Model>()) {
            modelContext.delete(row)
        }
        for slice in slices {
            guard let projection = try Model.project(slice.projection, entityID: slice.entityID) else {
                continue
            }
            modelContext.insert(Model.make(projection))
        }
    }

    private func replace<Model: FTProjectable>(
        _ type: Model.Type,
        entityID: UUID,
        expecting eventIDs: [UUID]
    ) throws {
        let slice = try eventLog.projection(
            entityType: Model.ftEntityType,
            entityID: entityID,
            supportedSchemaVersion: FTEntity.schemaVersion
        )
        if !slice.requiresUpgrade {
            let stored = Set(slice.events.map(\.id))
            if let missing = eventIDs.first(where: { !stored.contains($0) }) {
                throw FTProjectorError.eventNotStored(missing)
            }
        }

        let projection = try Model.project(slice, entityID: entityID)
        let rows = try modelContext.fetch(FetchDescriptor<Model>())
            .filter { $0.ftEntityID == entityID }

        guard let projection else {
            for row in rows {
                modelContext.delete(row)
            }
            return
        }

        if let row = rows.first {
            row.apply(projection)
            for duplicate in rows.dropFirst() {
                modelContext.delete(duplicate)
            }
        } else {
            modelContext.insert(Model.make(projection))
        }
    }

    private func saveIfNeeded() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}

private struct FTEntityKey: Hashable {
    let entityType: String
    let entityID: UUID
}

enum FTProjectorError: Error, Equatable {
    case unexpectedEntityType(String)
    case eventNotStored(UUID)
}

enum FTProjectionError: Error, Equatable {
    case requiresUpgrade(String, UUID)
    case foreignEvent(UUID)
    case incompleteCreate(UUID)
}
