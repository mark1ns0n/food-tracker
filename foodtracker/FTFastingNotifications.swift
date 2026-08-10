//
//  FTFastingNotifications.swift
//  foodtracker
//
//  F01.14 — the one place that decides which fasting reminder is pending.
//

import Foundation
// The notification centre is not `Sendable`, and scheduling has always meant
// handing it to its own authorization callback.
@preconcurrency import UserNotifications

/// Which single reminder the fasting schedule currently earns.
///
/// A plan rather than a pair of "schedule this" calls, because there is only
/// ever one pending reminder and two callers now decide it: the tab, from the
/// button the user just pressed, and the pull path, from a schedule another
/// device changed. Two imperative copies of the same three requests would drift
/// the moment one of them learned something the other did not.
enum FTFastingNotificationPlan: Equatable {
    /// Nothing pending: no schedule, or a fast whose end has already passed.
    case none
    /// No fast running — remind the user daily when it is time to start one.
    case start(hour: Int, minute: Int)
    /// A fast is running — remind the user when it is over.
    case end(after: TimeInterval)
}

extension FTFastingNotificationPlan {
    /// The plan a state implies, so a schedule that arrived over sync produces
    /// the same reminder it would have produced had the user set it here.
    ///
    /// `now` is a parameter because the remaining time of a fast started on
    /// another device is the whole of the calculation, and a fast that has
    /// already run out earns no reminder at all: its end is in the past, and the
    /// start reminder belongs to the user who stopped it.
    init(schedule: FTFastingScheduleProjection?, now: Date) {
        guard let schedule else {
            self = .none
            return
        }
        guard let activeStartDate = schedule.activeStartDate else {
            self = .start(hour: schedule.startHour, minute: schedule.startMinute)
            return
        }
        let remaining = activeStartDate
            .addingTimeInterval(TimeInterval(schedule.durationMinutes * 60))
            .timeIntervalSince(now)
        self = remaining > 0 ? .end(after: remaining) : .none
    }
}

/// The port the pull path and the tab both go through, so a test can watch what
/// was planned without a notification centre — and without asking the user for
/// permission in the middle of a test run.
@MainActor
protocol FTFastingNotificationScheduling {
    func apply(_ plan: FTFastingNotificationPlan)
}

/// The real one.
@MainActor
struct FTFastingNotifications: FTFastingNotificationScheduling {
    nonisolated static let startIdentifier = "fasting.start"
    nonisolated static let endIdentifier = "fasting.end"

    /// Cancel first, then schedule what the plan asks for: the two reminders are
    /// mutually exclusive, and the one being replaced is usually the one that
    /// would fire wrongly.
    func apply(_ plan: FTFastingNotificationPlan) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.startIdentifier, Self.endIdentifier]
        )
        guard plan != .none else { return }

        // Authorization is asked for on both branches, not just the daily start
        // reminder as before. A fast can now begin on the other device, so the
        // end reminder can be the first notification this install ever
        // schedules — and one scheduled without permission is a reminder that
        // silently never arrives.
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted, let request = Self.request(for: plan) else { return }
            center.add(request)
        }
    }

    nonisolated static func request(for plan: FTFastingNotificationPlan) -> UNNotificationRequest? {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch plan {
        case .none:
            return nil
        case let .start(hour, minute):
            content.title = "Time to fast"
            content.body = "Open the app and tap Start to begin your fast."
            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute
            return UNNotificationRequest(
                identifier: startIdentifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: dateComponents,
                    repeats: true
                )
            )
        case let .end(after):
            content.title = "Fasting complete!"
            content.body = "You did it! Open the app and tap Stop."
            return UNNotificationRequest(
                identifier: endIdentifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: after, repeats: false)
            )
        }
    }
}
