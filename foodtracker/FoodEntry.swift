//
//  FoodEntry.swift
//  foodtracker
//
//  Created by Codex on 09.02.2026.
//

import Foundation
import SwiftData

@Model
final class FoodEntry {
    var name: String
    var amount: Double
    var createdAt: Date

    private static let secondsInDay: TimeInterval = 60 * 60 * 24
    private static let expirationInterval: TimeInterval = secondsInDay * 30

    init(name: String, amount: Double, createdAt: Date = Date()) {
        self.name = name
        self.amount = amount
        self.createdAt = createdAt
    }

    var expirationDate: Date {
        createdAt.addingTimeInterval(Self.expirationInterval)
    }

    var daysRemaining: Int {
        let remainingTime = expirationDate.timeIntervalSinceNow
        guard remainingTime > 0 else { return 0 }
        return Int(ceil(remainingTime / Self.secondsInDay))
    }

    var isExpired: Bool {
        expirationDate.timeIntervalSinceNow <= 0
    }
}
