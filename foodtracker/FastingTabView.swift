//
//  FastingTabView.swift
//  foodtracker
//
//  Created by Ivan Markin on 03.03.2026.
//

import OSLog
import SwiftUI
import SwiftData

struct FastingTabView: View {
    // No `modelContext`: the schedule and the debts change by being written to
    // the log first, and this view has no way left to touch a row directly.
    @Environment(\.ftWriter) private var writer
    private let notifications = FTFastingNotifications()
    @Query private var entries: [FastingEntry]
    @Query(sort: \FastingDebt.createdAt, order: .reverse) private var debts: [FastingDebt]

    @State private var now = Date()
    @State private var timerTask: Timer?
    @State private var writeFailure: String?

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
            .overlay {
                if let writeFailure {
                    NotificationOverlay(message: writeFailure)
                }
            }
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
                    deleteSchedule()
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
                let recorded = write {
                    try $0.createFastingSchedule(
                        startHour: hour,
                        startMinute: minute,
                        durationMinutes: durationMinutes
                    )
                }
                guard recorded else { return }
                notifications.apply(.start(hour: hour, minute: minute))
            }
        }
    }

    // MARK: - Actions

    // The schedule and the debts reach the tables through `FTWriter` only, so
    // what is on screen is what a replay of the log would rebuild. The
    // notifications stay here, next to the call that earned them, and are only
    // (re)scheduled once the change is actually in the log: reminding the user
    // about a fast that was never recorded would be a lie the log cannot back.
    //
    // What each button implies is stated as a plan (F01.14); the requests
    // themselves live in `FTFastingNotifications`, which the pull path uses too.

    private func startFasting(entry: FastingEntry) {
        let recorded = withAnimation { write { try $0.startFast() } }
        guard recorded else { return }
        notifications.apply(.end(after: TimeInterval(entry.durationMinutes * 60)))
    }

    private func stopFasting(entry: FastingEntry) {
        let recorded = withAnimation { write { try $0.stopFast() } }
        guard recorded else { return }
        notifications.apply(.start(hour: entry.startHour, minute: entry.startMinute))
    }

    private func iAte(entry: FastingEntry) {
        guard let start = entry.activeStartDate else { return }

        // The arithmetic stays in the view: it is the one holding the clock, and
        // the minutes it works out here are an observation of this moment that
        // travels ready-made rather than something a replay recomputes.
        let elapsedSeconds = Date().timeIntervalSince(start)
        let totalSeconds = TimeInterval(entry.durationMinutes * 60)
        let remainingSeconds = max(0, totalSeconds - elapsedSeconds)
        let missedMinutes = Int(ceil(remainingSeconds / 60))

        let recorded = withAnimation { write { try $0.recordIAte(missedMinutes: missedMinutes) } }
        guard recorded else { return }
        notifications.apply(.start(hour: entry.startHour, minute: entry.startMinute))
    }

    private func deleteSchedule() {
        let recorded = withAnimation { write { try $0.deleteFastingSchedule() } }
        guard recorded else { return }
        notifications.apply(.none)
    }

    /// Runs a mutation through the writer and says whether it happened.
    ///
    /// A failed append changes nothing — the writer projects only what the log
    /// accepted — so the row on screen is still the truth and the message is the
    /// whole of the feedback.
    private func write(_ mutation: (FTWriter) throws -> Void) -> Bool {
        guard let writer else {
            // A preview builds this view without going through `foodtrackerApp`,
            // so it has no log to write to; it shows the data and refuses to
            // change it.
            showWriteFailure()
            return false
        }
        do {
            try mutation(writer)
            return true
        } catch {
            Logger.ftSync.error("Could not record the change: \(String(describing: error))")
            showWriteFailure()
            return false
        }
    }

    private func showWriteFailure() {
        writeFailure = "Could not save the change."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            writeFailure = nil
        }
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
