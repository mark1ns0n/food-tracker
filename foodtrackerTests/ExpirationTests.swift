//
//  ExpirationTests.swift
//  foodtrackerTests
//
//  F01.03 — expiry hides a row, it does not delete it.
//

import Foundation
import Testing

@testable import foodtracker

/// The 30-day window on delivery and dine-in rows.
///
/// Until F01.03 `FoodTabView.onAppear` physically deleted anything past the
/// window, so the rule was enforced in two places at once — a filter for the
/// screen and a delete for the store. These tests pin the filter, which is now
/// the only one: nothing outside the window is removed, it simply stops being
/// active.
struct ExpirationTests {
    private static let day: TimeInterval = 60 * 60 * 24

    private static func daysAgo(_ days: Double) -> Date {
        Date().addingTimeInterval(-day * days)
    }

    @Test
    func aDeliveryPastThirtyDaysIsExpiredAndHasNoDaysLeft() {
        let entry = FoodEntry(name: "Суши", amount: 1200, createdAt: Self.daysAgo(31))

        #expect(entry.isExpired)
        #expect(entry.daysRemaining == 0)
    }

    @Test
    func aDeliveryInsideThirtyDaysIsStillActive() {
        let entry = FoodEntry(name: "Суши", amount: 1200, createdAt: Self.daysAgo(29))

        #expect(!entry.isExpired)
        #expect(entry.daysRemaining == 1)
    }

    @Test
    func aDineInPastThirtyDaysIsExpiredAndHasNoDaysLeft() {
        let entry = DineInEntry(name: "Кафе", createdAt: Self.daysAgo(31))

        #expect(entry.isExpired)
        #expect(entry.daysRemaining == 0)
    }

    @Test
    func aDineInInsideThirtyDaysIsStillActive() {
        let entry = DineInEntry(name: "Кафе", createdAt: Self.daysAgo(29))

        #expect(!entry.isExpired)
        #expect(entry.daysRemaining == 1)
    }
}
