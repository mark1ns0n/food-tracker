//
//  FastingDebt.swift
//  foodtracker
//
//  Created by Ivan Markin on 03.03.2026.
//

import Foundation
import SwiftData

@Model
final class FastingDebt {
    /// How many minutes of fasting were missed
    var missedMinutes: Int
    /// When the user pressed "I ate"
    var createdAt: Date

    init(missedMinutes: Int, createdAt: Date = Date()) {
        self.missedMinutes = missedMinutes
        self.createdAt = createdAt
    }

    var formattedDebt: String {
        let hours = missedMinutes / 60
        let mins = missedMinutes % 60
        if hours == 0 {
            return "\(mins)m"
        }
        if mins == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(mins)m"
    }
}
