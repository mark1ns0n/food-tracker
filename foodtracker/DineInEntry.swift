//
//  DineInEntry.swift
//  foodtracker
//
//  Created by Codex on 25.01.2026.
//

import Foundation
import SwiftData

@Model
final class DineInEntry {
    var name: String
    var createdAt: Date

    private static let secondsInDay: TimeInterval = 60 * 60 * 24
    private static let expirationInterval: TimeInterval = secondsInDay * 30

    init(name: String, createdAt: Date = Date()) {
        self.name = name
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
