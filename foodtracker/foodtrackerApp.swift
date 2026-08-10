//
//  foodtrackerApp.swift
//  foodtracker
//
//  Created by Ivan Markin on 15.01.2026.
//

import CoreSync
import SwiftUI
import SwiftData

@main
struct foodtrackerApp: App {
    let sharedModelContainer: ModelContainer
    private let eventStore: SQLiteEventStore
    private let writer: FTWriter

    init() {
        let schema = Schema([
            Item.self,
            FoodEntry.self,
            SavedName.self,
            DineInEntry.self,
            FastingEntry.self,
            FastingDebt.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            sharedModelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        do {
            // F01.05 left a store that would not open as a log line, because
            // nothing wrote to it yet. From here on a grocery mutation is an
            // event before it is a row: an app running without its log would
            // accept edits nobody records, and the first replay would erase
            // them. Refusing to start is the smaller loss, and it is what
            // workhardercomrade does with the same failure.
            eventStore = try FTSyncComposition.makeEventStore()
        } catch {
            fatalError("Could not open the event store: \(error)")
        }

        let context = sharedModelContainer.mainContext
        writer = FTWriter(
            modelContext: context,
            store: eventStore,
            projector: FTProjector(eventLog: eventStore, modelContext: context)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.ftWriter, writer)
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    BackupService.shared.performAutoBackupIfNeeded(context: context)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Injection

/// The writer reaches the views through the environment rather than through
/// initializers, so the view tree between the app and a tab stays untouched.
///
/// Optional on purpose: a SwiftUI preview builds a view without going through
/// `foodtrackerApp`, and a preview that mutated a real log would be writing the
/// developer's own events. A view with no writer shows data and refuses to
/// change it.
private struct FTWriterEnvironmentKey: EnvironmentKey {
    static var defaultValue: FTWriter? { nil }
}

extension EnvironmentValues {
    var ftWriter: FTWriter? {
        get { self[FTWriterEnvironmentKey.self] }
        set { self[FTWriterEnvironmentKey.self] = newValue }
    }
}
