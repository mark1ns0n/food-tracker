//
//  foodtrackerApp.swift
//  foodtracker
//
//  Created by Ivan Markin on 15.01.2026.
//

import SwiftUI
import SwiftData

@main
struct foodtrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            FoodEntry.self,
            SavedName.self,
            DineInEntry.self,
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
        }
        .modelContainer(sharedModelContainer)
    }
}
