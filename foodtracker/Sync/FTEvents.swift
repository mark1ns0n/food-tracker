//
//  FTEvents.swift
//  foodtracker
//
//  F01.06 — the wire format: entity types, payloads, deterministic ids.
//

import CoreSync
import Foundation

// MARK: - Entity types

/// The six `ft.*` entity types. The backend has no foodtracker-specific schema:
/// these are just new `entityType` strings in the shared event table (B01).
enum FTEntity {
    static let grocery = "ft.Grocery"
    static let delivery = "ft.DeliveryEntry"
    static let dineIn = "ft.DineInEntry"
    static let savedName = "ft.SavedName"
    static let fastingSchedule = "ft.FastingSchedule"
    static let fastingDebt = "ft.FastingDebt"

    static let schemaVersion = 1

    /// What this client can read, keyed the way the sync engine wants it
    /// (the `SavingsEventStore.capabilities` shape). Everything else the
    /// account holds (`su.*`, `ban.*`, …) still arrives — the server does not
    /// filter by these — lands in the store and is blocked as requiring
    /// upgrade, the same stance kopilka takes. In F01.16 this table travels to
    /// the kit, where super-app merges it into its own capabilities (F01.17).
    static let capabilities: [String: Int] = [
        grocery: schemaVersion,
        delivery: schemaVersion,
        dineIn: schemaVersion,
        savedName: schemaVersion,
        fastingSchedule: schemaVersion,
        fastingDebt: schemaVersion,
    ]
}

// MARK: - Wire tokens

/// The grocery type as it travels, which is deliberately **not**
/// `GroceryType.rawValue`.
///
/// Those raw values are the Russian labels shown on screen ("Основа", "Гарнир",
/// "Салат"), because the enum doubles as its own display string. Putting them on
/// the wire would make a copy edit a schema change: rename the label and every
/// event written before it stops decoding. The mapping is fixed here instead,
/// while the log still holds zero `ft.*` events and it costs nothing.
enum FTGroceryTypeToken {
    static func token(for type: GroceryType) -> String {
        switch type {
        case .main: "main"
        case .side: "side"
        case .salad: "salad"
        }
    }

    static func type(from token: String) -> GroceryType? {
        switch token {
        case "main": .main
        case "side": .side
        case "salad": .salad
        default: nil
        }
    }
}

// MARK: - Payloads

/// Every field is optional on purpose: `create` fills them all, `update` carries
/// only what changed, and a decoded payload says which keys the event actually
/// held.
///
/// Only `FTFastingSchedulePayload.activeStartDate` needs the sharper
/// distinction between "key absent" and "explicit null" — it is the one field
/// the app clears (stop, "I Ate"). Everywhere else an absent key simply means
/// "not part of this event".
struct FTGroceryPayload: Equatable {
    var name: String?
    var status: ItemStatus?
    var type: GroceryType?
    var createdAt: Date?

    var value: JSONValue {
        var object: [String: JSONValue] = [:]
        if let name { object["name"] = .string(name) }
        if let status { object["status"] = .string(status.rawValue) }
        if let type { object["type"] = .string(FTGroceryTypeToken.token(for: type)) }
        if let createdAt { object["createdAt"] = .string(FTDate.string(createdAt)) }
        return .object(object)
    }

    static func decode(_ payload: JSONValue) -> FTGroceryPayload {
        guard case let .object(object) = payload else { return FTGroceryPayload() }
        return FTGroceryPayload(
            name: object.string("name"),
            status: object.string("status").flatMap(ItemStatus.init(rawValue:)),
            type: object.string("type").flatMap(FTGroceryTypeToken.type(from:)),
            createdAt: object.date("createdAt")
        )
    }
}

struct FTDeliveryPayload: Equatable {
    var name: String?
    var amount: Double?
    var createdAt: Date?

    var value: JSONValue {
        var object: [String: JSONValue] = [:]
        if let name { object["name"] = .string(name) }
        if let amount { object["amount"] = .number(amount) }
        if let createdAt { object["createdAt"] = .string(FTDate.string(createdAt)) }
        return .object(object)
    }

    static func decode(_ payload: JSONValue) -> FTDeliveryPayload {
        guard case let .object(object) = payload else { return FTDeliveryPayload() }
        return FTDeliveryPayload(
            name: object.string("name"),
            amount: object.number("amount"),
            createdAt: object.date("createdAt")
        )
    }
}

struct FTDineInPayload: Equatable {
    var name: String?
    var createdAt: Date?

    var value: JSONValue {
        var object: [String: JSONValue] = [:]
        if let name { object["name"] = .string(name) }
        if let createdAt { object["createdAt"] = .string(FTDate.string(createdAt)) }
        return .object(object)
    }

    static func decode(_ payload: JSONValue) -> FTDineInPayload {
        guard case let .object(object) = payload else { return FTDineInPayload() }
        return FTDineInPayload(
            name: object.string("name"),
            createdAt: object.date("createdAt")
        )
    }
}

struct FTSavedNamePayload: Equatable {
    var value: String?
    var lastUsed: Date?

    var jsonValue: JSONValue {
        var object: [String: JSONValue] = [:]
        if let value { object["value"] = .string(value) }
        if let lastUsed { object["lastUsed"] = .string(FTDate.string(lastUsed)) }
        return .object(object)
    }

    static func decode(_ payload: JSONValue) -> FTSavedNamePayload {
        guard case let .object(object) = payload else { return FTSavedNamePayload() }
        return FTSavedNamePayload(
            value: object.string("value"),
            lastUsed: object.date("lastUsed")
        )
    }
}

struct FTFastingSchedulePayload: Equatable {
    var startHour: Int?
    var startMinute: Int?
    var durationMinutes: Int?
    /// Outer `nil` — the event did not mention it, leave the field alone.
    /// Inner `nil` — an explicit JSON null, meaning "clear it": the fast stopped.
    var activeStartDate: Date??

    init(
        startHour: Int? = nil,
        startMinute: Int? = nil,
        durationMinutes: Int? = nil,
        activeStartDate: Date?? = nil
    ) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.activeStartDate = activeStartDate
    }

    var value: JSONValue {
        var object: [String: JSONValue] = [:]
        if let startHour { object["startHour"] = .number(Double(startHour)) }
        if let startMinute { object["startMinute"] = .number(Double(startMinute)) }
        if let durationMinutes { object["durationMinutes"] = .number(Double(durationMinutes)) }
        if let activeStartDate {
            object["activeStartDate"] = activeStartDate
                .map { .string(FTDate.string($0)) } ?? .null
        }
        return .object(object)
    }

    static func decode(_ payload: JSONValue) -> FTFastingSchedulePayload {
        guard case let .object(object) = payload else { return FTFastingSchedulePayload() }
        var activeStartDate: Date??
        switch object["activeStartDate"] {
        case .none:
            activeStartDate = nil
        case .some(.null):
            activeStartDate = .some(nil)
        case let .some(value):
            // A malformed date is treated as "not mentioned" rather than as a
            // clear: guessing "stop the fast" from a string nobody can parse
            // would lose the running fast.
            if case let .string(text) = value, let date = FTDate.date(text) {
                activeStartDate = .some(date)
            } else {
                activeStartDate = nil
            }
        }
        return FTFastingSchedulePayload(
            startHour: object.int("startHour"),
            startMinute: object.int("startMinute"),
            durationMinutes: object.int("durationMinutes"),
            activeStartDate: activeStartDate
        )
    }
}

struct FTFastingDebtPayload: Equatable {
    var missedMinutes: Int?
    var createdAt: Date?

    var value: JSONValue {
        var object: [String: JSONValue] = [:]
        if let missedMinutes { object["missedMinutes"] = .number(Double(missedMinutes)) }
        if let createdAt { object["createdAt"] = .string(FTDate.string(createdAt)) }
        return .object(object)
    }

    static func decode(_ payload: JSONValue) -> FTFastingDebtPayload {
        guard case let .object(object) = payload else { return FTFastingDebtPayload() }
        return FTFastingDebtPayload(
            missedMinutes: object.int("missedMinutes"),
            createdAt: object.date("createdAt")
        )
    }
}

// MARK: - Identifiers

/// Deterministic ids, so two devices that name the same thing name it the same
/// way.
///
/// `namespace` is fixed forever: change it and every id derived from it moves,
/// which would fork every deterministic entity in the log.
enum FTIDs {
    static let namespace = UUID(uuidString: "1354AF44-9C79-4802-A41D-B3250B97829E")!

    /// One saved name is one entity, whatever case it was typed in, so `create`
    /// acts as an upsert (the `ct.Rule` pattern).
    static func savedName(value: String) -> UUID {
        UUIDVersion5.make(
            namespace: namespace,
            name: "ft.savedname." + value.lowercased()
        )
    }

    /// The fasting schedule is a singleton — the app reads `entries.first` — so
    /// it gets one id rather than a row id (the `ct.Profile`/U01 pattern).
    static func fastingSchedule() -> UUID {
        UUIDVersion5.make(namespace: namespace, name: "ft.fasting.schedule")
    }

    /// Backfill event id for a row that already has its own identity: derived
    /// from the entity id, so re-running the migration writes the same event and
    /// the store rejects it as a duplicate rather than doubling the row.
    static func backfillEventID(entityID: UUID) -> UUID {
        UUIDVersion5.make(
            namespace: namespace,
            name: "ft.backfill." + entityID.uuidString.lowercased()
        )
    }

    /// Backfill event id for the entities whose *entity* id is shared across
    /// devices — saved names and the schedule.
    ///
    /// Per device on purpose (the U01 pattern): both devices legitimately hold
    /// their own version of the same entity, so their backfills must be two
    /// events that LWW resolves, not one event id that silently swallows the
    /// second device's state.
    static func backfillEventID(deviceID: UUID, name: String) -> UUID {
        UUIDVersion5.make(
            namespace: namespace,
            name: "ft.backfill." + deviceID.uuidString.lowercased() + "." + name
        )
    }
}

// MARK: - Dates

/// ISO-8601 with an offset (the B01 convention), written in UTC.
enum FTDate {
    static func string(_ date: Date) -> String {
        ISO8601DateFormatter.string(
            from: date,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        )
    }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        // Events written by another client may omit the fraction.
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private extension [String: JSONValue] {
    func string(_ key: String) -> String? {
        guard case let .some(.string(value)) = self[key] else { return nil }
        return value
    }

    func number(_ key: String) -> Double? {
        guard case let .some(.number(value)) = self[key] else { return nil }
        return value
    }

    func int(_ key: String) -> Int? {
        number(key).map(Int.init)
    }

    func date(_ key: String) -> Date? {
        string(key).flatMap(FTDate.date)
    }
}
