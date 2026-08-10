//
//  foodtrackerApp.swift
//  foodtracker
//
//  Created by Ivan Markin on 15.01.2026.
//

import AppShell
import CoreSync
import SwiftUI
import SwiftData

@main
struct foodtrackerApp: App {
    let sharedModelContainer: ModelContainer
    private let eventStore: SQLiteEventStore
    private let writer: FTWriter
    private let backfill: FTBackfillService
    private let syncCoordinator: FTSyncCoordinator?
    @Environment(\.scenePhase) private var scenePhase

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

        // The bootstrap owns the same store `makeEventStore()` would open, plus
        // the transport behind it — one instance, not two connections to one
        // database. Failing to compose it (keychain trouble, usually) only
        // costs the network half: the bare store keeps the app fully
        // offline-functional, which is the failure mode F01.13 asks for.
        if let bootstrap = FTSyncComposition.makeSyncBootstrap() {
            eventStore = bootstrap.eventStore
            syncCoordinator = FTSyncCoordinator(bootstrap: bootstrap)
        } else {
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
            syncCoordinator = nil
        }

        let context = sharedModelContainer.mainContext
        let projector = FTProjector(eventLog: eventStore, modelContext: context)
        writer = FTWriter(modelContext: context, store: eventStore, projector: projector)
        backfill = FTBackfillService(
            modelContext: context,
            store: eventStore,
            projector: projector
        )
        writer.onLocalEventAppended = { [syncCoordinator] in
            syncCoordinator?.noteLocalMutation()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.ftWriter, writer)
                .onAppear {
                    do {
                        // Before the auto-backup, so what gets backed up is the
                        // state the replay just rebuilt, not the tables it was
                        // about to rewrite.
                        try backfill.runIfNeeded()
                    } catch {
                        // The same stance as the store that would not open: an
                        // app that keeps running here goes on accepting edits
                        // while rows the log has never heard of sit in the
                        // store — and the first sync would push fresh events
                        // with no history behind them.
                        fatalError("Could not backfill the event log: \(error)")
                    }
                    let context = sharedModelContainer.mainContext
                    BackupService.shared.performAutoBackupIfNeeded(context: context)
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                syncCoordinator?.noteScenePhaseActive()
            }
        }
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
