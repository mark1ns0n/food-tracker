//
//  FastingEntry.swift
//  foodtracker
//
//  Created by Ivan Markin on 03.03.2026.
//

import Foundation
import SwiftData

@Model
final class FastingEntry {
    /// Scheduled start time (hour & minute only, repeats daily)
    var startHour: Int
    var startMinute: Int
    /// Duration of the fast in minutes
    var durationMinutes: Int
    /// When the user actually pressed Start (nil = not currently fasting)
    var activeStartDate: Date?
    var createdAt: Date

    init(startHour: Int, startMinute: Int, durationMinutes: Int, createdAt: Date = Date()) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.activeStartDate = nil
        self.createdAt = createdAt
    }

    var isFasting: Bool {
        activeStartDate != nil
    }

    var expectedEndDate: Date? {
        guard let start = activeStartDate else { return nil }
        return start.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    var formattedStartTime: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var formattedDuration: String {
        let hours = durationMinutes / 60
        let mins = durationMinutes % 60
        if mins == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(mins)m"
    }
}
