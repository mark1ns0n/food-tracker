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

    init(name: String, amount: Double, createdAt: Date = Date()) {
        self.name = name
        self.amount = amount
        self.createdAt = createdAt
    }

    var isExpired: Bool {
        let thirtyDays: TimeInterval = 60 * 60 * 24 * 30
        return Date().timeIntervalSince(createdAt) > thirtyDays
    }
}
