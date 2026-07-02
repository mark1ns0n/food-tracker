//
//  FastingTabView.swift
//  foodtracker
//
//  Created by Ivan Markin on 03.03.2026.
//

import SwiftUI
import SwiftData
import UserNotifications

struct FastingTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [FastingEntry]
    @Query(sort: \FastingDebt.createdAt, order: .reverse) private var debts: [FastingDebt]

    @State private var now = Date()
    @State private var timerTask: Timer?

    private var entry: FastingEntry? { entries.first }

    private var totalDebtMinutes: Int {
        debts.reduce(0) { $0 + $1.missedMinutes }
    }

    var body: some View {
        NavigationStack {
            List {
                if let entry {
                    settingsSection(entry: entry)

                    if entry.isFasting {
                        activeTimerSection(entry: entry)
                        actionButtonsSection(entry: entry)
                    } else {
                        Section {
                            Button(action: { startFasting(entry: entry) }) {
                                Label("Start Fasting", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }

                    if totalDebtMinutes > 0 {
                        debtSection
                    }
                } else {
                    setupSection
                }
            }
            .navigationTitle("Fasting")
            .onAppear {
                timerTask = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    Task { @MainActor in
                        now = Date()
                    }
                }
            }
            .onDisappear {
                timerTask?.invalidate()
                timerTask = nil
            }
        }
    }

    // MARK: - Sections

    private func settingsSection(entry: FastingEntry) -> some View {
        Section("Schedule") {
            HStack {
                Label("Start time", systemImage: "clock")
                Spacer()
                Text(entry.formattedStartTime)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Duration", systemImage: "hourglass")
                Spacer()
                Text(entry.formattedDuration)
                    .foregroundStyle(.secondary)
            }
            if !entry.isFasting {
                Button("Change Settings", role: .destructive) {
                    deleteEntry(entry)
                }
            }
        }
    }

    private func activeTimerSection(entry: FastingEntry) -> some View {
        Section("Active Fast") {
            if let start = entry.activeStartDate, let end = entry.expectedEndDate {
                let elapsed = now.timeIntervalSince(start)
                let total = end.timeIntervalSince(start)
                let remaining = max(0, total - elapsed)
                let progress = min(1.0, elapsed / total)

                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .tint(remaining == 0 ? .green : .orange)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Elapsed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatInterval(elapsed))
                                .font(.headline.monospacedDigit())
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatInterval(remaining))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(remaining == 0 ? .green : .primary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func actionButtonsSection(entry: FastingEntry) -> some View {
        Section {
            HStack(spacing: 12) {
                Button(action: { stopFasting(entry: entry) }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(action: { iAte(entry: entry) }) {
                    Label("I Ate", systemImage: "fork.knife")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var debtSection: some View {
        Section("Debt") {
            HStack {
                Label("Total debt", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Spacer()
                Text(formatDebtMinutes(totalDebtMinutes))
                    .font(.headline)
                    .foregroundStyle(.red)
            }

            ForEach(debts) { debt in
                HStack {
                    Text(debt.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+" + debt.formattedDebt)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var setupSection: some View {
        Section {
            FastingSetupView { hour, minute, durationMinutes in
                let newEntry = FastingEntry(
                    startHour: hour,
                    startMinute: minute,
                    durationMinutes: durationMinutes
                )
                modelContext.insert(newEntry)
                scheduleStartNotification(hour: hour, minute: minute)
            }
        }
    }

    // MARK: - Actions

    private func startFasting(entry: FastingEntry) {
        withAnimation {
            entry.activeStartDate = Date()
        }
        cancelAllFastingNotifications()
        scheduleEndNotification(after: entry.durationMinutes)
    }

    private func stopFasting(entry: FastingEntry) {
        withAnimation {
            entry.activeStartDate = nil
        }
        cancelAllFastingNotifications()
        scheduleStartNotification(hour: entry.startHour, minute: entry.startMinute)
    }

    private func iAte(entry: FastingEntry) {
        guard let start = entry.activeStartDate else { return }

        let elapsedSeconds = Date().timeIntervalSince(start)
        let totalSeconds = TimeInterval(entry.durationMinutes * 60)
        let remainingSeconds = max(0, totalSeconds - elapsedSeconds)
        let missedMinutes = Int(ceil(remainingSeconds / 60))

        if missedMinutes > 0 {
            let debt = FastingDebt(missedMinutes: missedMinutes)
            modelContext.insert(debt)
        }

        withAnimation {
            entry.activeStartDate = nil
        }
        cancelAllFastingNotifications()
        scheduleStartNotification(hour: entry.startHour, minute: entry.startMinute)
    }

    private func deleteEntry(_ entry: FastingEntry) {
        cancelAllFastingNotifications()
        withAnimation {
            modelContext.delete(entry)
        }
    }

    // MARK: - Notifications

    private func scheduleStartNotification(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Time to fast"
            content.body = "Open the app and tap Start to begin your fast."
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

            let request = UNNotificationRequest(identifier: "fasting.start", content: content, trigger: trigger)
            center.add(request)
        }
    }

    private func scheduleEndNotification(after durationMinutes: Int) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Fasting complete!"
        content.body = "You did it! Open the app and tap Stop."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(durationMinutes * 60),
            repeats: false
        )

        let request = UNNotificationRequest(identifier: "fasting.end", content: content, trigger: trigger)
        center.add(request)
    }

    private func cancelAllFastingNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["fasting.start", "fasting.end"])
    }

    // MARK: - Formatting

    private func formatInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func formatDebtMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}

// MARK: - Setup View

struct FastingSetupView: View {
    let onSave: (Int, Int, Int) -> Void

    @State private var startTime = Calendar.current.date(
        from: DateComponents(hour: 20, minute: 0)
    ) ?? Date()
    @State private var durationHours = 16
    @State private var durationMinutes = 0

    var body: some View {
        VStack(spacing: 16) {
            DatePicker(
                "Start Time",
                selection: $startTime,
                displayedComponents: .hourAndMinute
            )
            .environment(\.locale, Locale(identifier: "en_GB"))

            Stepper("Duration: \(durationHours)h \(durationMinutes)m", onIncrement: {
                incrementDuration()
            }, onDecrement: {
                decrementDuration()
            })

            Button(action: save) {
                Label("Save Schedule", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }

    private func incrementDuration() {
        durationMinutes += 5
        if durationMinutes >= 60 {
            durationMinutes = 0
            durationHours += 1
        }
        if durationHours >= 24 {
            durationHours = 24
            durationMinutes = 0
        }
    }

    private func decrementDuration() {
        durationMinutes -= 5
        if durationMinutes < 0 {
            if durationHours > 0 {
                durationHours -= 1
                durationMinutes = 55
            } else {
                durationMinutes = 0
            }
        }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let hour = components.hour ?? 20
        let minute = components.minute ?? 0
        let totalMinutes = durationHours * 60 + durationMinutes
        guard totalMinutes > 0 else { return }
        onSave(hour, minute, totalMinutes)
    }
}

#Preview {
    FastingTabView()
        .modelContainer(for: [FastingEntry.self, FastingDebt.self], inMemory: true)
}
