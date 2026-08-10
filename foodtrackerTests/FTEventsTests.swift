//
//  FTEventsTests.swift
//  foodtrackerTests
//
//  F01.06 — the wire format holds still.
//

import CoreSync
import Foundation
import Testing

@testable import foodtracker

/// Deterministic ids are a promise to every other device and to the backfill:
/// the same input has to give the same UUID today, after a refactor, and on a
/// machine that has never seen this log.
struct FTIDsTests {
    @Test
    func theSameNameGivesTheSameIDTwice() {
        #expect(FTIDs.savedName(value: "Talabat") == FTIDs.savedName(value: "Talabat"))
        #expect(FTIDs.fastingSchedule() == FTIDs.fastingSchedule())
    }

    @Test
    func savedNameIgnoresCase() {
        // "Talabat Mart" typed on one device and "talabat mart" on another are
        // one saved name, not two — that is what makes create an upsert.
        #expect(FTIDs.savedName(value: "Talabat") == FTIDs.savedName(value: "talabat"))
        #expect(FTIDs.savedName(value: "TALABAT") == FTIDs.savedName(value: "talabat"))
    }

    @Test
    func differentNamesGiveDifferentIDs() {
        #expect(FTIDs.savedName(value: "Talabat") != FTIDs.savedName(value: "Deliveroo"))
    }

    /// Snapshot, not a tautology: these constants are what a second device and
    /// the backfill will compute. If the namespace or a name recipe is ever
    /// edited, every id derived from it moves and the log forks — this test is
    /// the tripwire for that, and it is meant to be hard to "fix".
    @Test
    func theIDRecipesMatchTheirRecordedValues() {
        #expect(
            FTIDs.namespace == UUID(uuidString: "1354AF44-9C79-4802-A41D-B3250B97829E")
        )
        #expect(
            FTIDs.savedName(value: "Talabat")
                == UUID(uuidString: "8C7733E3-7726-560C-8FF5-809EC2800C2B")
        )
        #expect(
            FTIDs.fastingSchedule()
                == UUID(uuidString: "B324FF52-15B6-518D-B3EB-96F99025E0C0")
        )
        #expect(
            FTIDs.backfillEventID(
                entityID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!
            ) == UUID(uuidString: "61FCA5BB-D4F2-50FF-8DD3-4244C54156A6")
        )
        #expect(
            FTIDs.backfillEventID(
                deviceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "ft.savedname.talabat"
            ) == UUID(uuidString: "4E916452-2B08-59B8-BE6E-4C44B0CCE70E")
        )
    }

    @Test
    func aBackfillEventIDIsPerDevice() {
        // Saved names and the schedule share an entity id across devices, so
        // their backfills must stay two distinguishable events for LWW to pick
        // between — one shared event id would swallow the second device's state.
        let first = FTIDs.backfillEventID(
            deviceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "ft.fasting.schedule"
        )
        let second = FTIDs.backfillEventID(
            deviceID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "ft.fasting.schedule"
        )
        #expect(first != second)
    }
}

/// Payloads survive the trip through `JSONValue`, and an `update` says exactly
/// which fields it carries — no more.
struct FTPayloadTests {
    /// Whole seconds: the ISO-8601 form keeps milliseconds, so a date built from
    /// a sub-millisecond `Date()` would not compare equal after a round trip.
    private let moment = Date(timeIntervalSince1970: 1_770_000_000)

    @Test
    func groceryRoundTrips() {
        let payload = FTGroceryPayload(
            name: "Рис",
            status: .used,
            type: .side,
            createdAt: moment
        )

        #expect(FTGroceryPayload.decode(payload.value) == payload)
    }

    @Test
    func theGroceryTypeTravelsAsAStableTokenNotItsRussianLabel() {
        let payload = FTGroceryPayload(type: .main)

        guard case let .object(object) = payload.value else {
            Issue.record("payload should encode as an object")
            return
        }
        #expect(object["type"] == .string("main"))
        #expect(object["type"] != .string(GroceryType.main.rawValue))
        #expect(FTGroceryPayload.decode(payload.value).type == .main)
    }

    @Test
    func anUnknownGroceryTypeTokenDecodesToNothingRatherThanGuessing() {
        let decoded = FTGroceryPayload.decode(.object(["type": .string("dessert")]))

        #expect(decoded.type == nil)
    }

    @Test
    func anUpdateCarriesOnlyTheFieldsItSets() {
        let payload = FTGroceryPayload(status: .available)

        #expect(payload.value == .object(["status": .string("available")]))
        #expect(FTGroceryPayload.decode(payload.value).name == nil)
        #expect(FTGroceryPayload.decode(payload.value).createdAt == nil)
    }

    @Test
    func deliveryAndDineInAndSavedNameRoundTrip() {
        let delivery = FTDeliveryPayload(name: "Суши", amount: 12.5, createdAt: moment)
        let dineIn = FTDineInPayload(name: "Кафе", createdAt: moment)
        let savedName = FTSavedNamePayload(value: "Talabat Mart", lastUsed: moment)

        #expect(FTDeliveryPayload.decode(delivery.value) == delivery)
        #expect(FTDineInPayload.decode(dineIn.value) == dineIn)
        #expect(FTSavedNamePayload.decode(savedName.jsonValue) == savedName)
    }

    @Test
    func fastingDebtRoundTrips() {
        let payload = FTFastingDebtPayload(missedMinutes: 45, createdAt: moment)

        #expect(FTFastingDebtPayload.decode(payload.value) == payload)
    }

    @Test
    func aRunningFastRoundTrips() {
        let payload = FTFastingSchedulePayload(
            startHour: 20,
            startMinute: 30,
            durationMinutes: 960,
            activeStartDate: .some(moment)
        )

        #expect(FTFastingSchedulePayload.decode(payload.value) == payload)
    }

    @Test
    func anAbsentActiveStartDateIsNotTheSameAsAnExplicitNull() {
        // "Не трогай это поле" против "останови пост" — the whole reason the
        // field is a double optional.
        let untouched = FTFastingSchedulePayload(durationMinutes: 960)
        let cleared = FTFastingSchedulePayload(activeStartDate: .some(nil))

        #expect(untouched.value == .object(["durationMinutes": .number(960)]))
        #expect(cleared.value == .object(["activeStartDate": .null]))

        #expect(FTFastingSchedulePayload.decode(untouched.value).activeStartDate == nil)

        let decodedClear = FTFastingSchedulePayload.decode(cleared.value)
        #expect(decodedClear.activeStartDate != nil)
        #expect(decodedClear.activeStartDate! == nil)
    }

    @Test
    func anUnparsableActiveStartDateIsTreatedAsUnmentioned() {
        // Reading "stop the fast" out of a string nobody can parse would throw
        // away a fast that is actually running.
        let decoded = FTFastingSchedulePayload.decode(
            .object(["activeStartDate": .string("not a date")])
        )

        #expect(decoded.activeStartDate == nil)
    }

    @Test
    func datesAreWrittenAsISO8601InUTC() {
        let payload = FTFastingDebtPayload(createdAt: Date(timeIntervalSince1970: 0))

        #expect(payload.value == .object(["createdAt": .string("1970-01-01T00:00:00.000Z")]))
    }

    @Test
    func aDateWithoutFractionalSecondsStillParses() {
        // Another client on the same log may omit the fraction.
        let decoded = FTFastingDebtPayload.decode(
            .object(["createdAt": .string("1970-01-01T00:00:00Z")])
        )

        #expect(decoded.createdAt == Date(timeIntervalSince1970: 0))
    }
}
