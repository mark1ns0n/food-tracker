//
//  foodtrackerApp.swift
//  foodtracker
//
//  Created by Ivan Markin on 15.01.2026.
//

import CoreSync
import OSLog
import SwiftUI
import SwiftData

@main
struct foodtrackerApp: App {
    /// The event log (F01.05). Nothing reads or writes it yet — the writers
    /// arrive in F01.08–F01.10 — so a store that fails to open is logged rather
    /// than fatal. When mutations actually route through it, that has to become
    /// a hard failure: silently running without a log would mean accepting edits
    /// nobody is recording.
    let eventStore: SQLiteEventStore? = {
        do {
            return try FTSyncComposition.makeEventStore()
        } catch {
            Logger(subsystem: FTSyncComposition.applicationIdentifier, category: "Sync")
                .error("Could not open the event store: \(String(describing: error))")
            return nil
        }
    }()

    var sharedModelContainer: ModelContainer = {
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
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    BackupService.shared.performAutoBackupIfNeeded(context: context)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
