//
//  BackupService.swift
//  foodtracker
//
//  Created by Claude on 08.03.2026.
//

import Foundation
import SwiftData

struct BackupData: Codable {
    var items: [ItemBackup]
    var foodEntries: [FoodEntryBackup]
    var savedNames: [SavedNameBackup]
    var dineInEntries: [DineInEntryBackup]
    var fastingEntries: [FastingEntryBackup]
    var fastingDebts: [FastingDebtBackup]
    var backupDate: Date
}

struct ItemBackup: Codable {
    var name: String
    var status: String
    var type: String?
    var createdAt: Date
}

struct FoodEntryBackup: Codable {
    var name: String
    var amount: Double
    var createdAt: Date
}

struct SavedNameBackup: Codable {
    var value: String
    var lastUsed: Date
}

struct DineInEntryBackup: Codable {
    var name: String
    var createdAt: Date
}

struct FastingEntryBackup: Codable {
    var startHour: Int
    var startMinute: Int
    var durationMinutes: Int
    var activeStartDate: Date?
    var createdAt: Date
}

struct FastingDebtBackup: Codable {
    var missedMinutes: Int
    var createdAt: Date
}

@MainActor
final class BackupService {
    static let shared = BackupService()

    private let lastBackupKey = "lastAutoBackupDate"

    // MARK: - Local Backup Directory

    private func backupDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupDir = docs.appendingPathComponent("Backups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: backupDir.path) {
            try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        }
        return backupDir
    }

    // MARK: - Export

    func exportBackup(context: ModelContext) throws -> URL {
        let data = try buildBackupData(context: context)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let dateString = dateFormatter.string(from: Date())
        let fileName = "backup_\(dateString).json"

        let fileURL = backupDirectory().appendingPathComponent(fileName)
        try jsonData.write(to: fileURL, options: .atomic)

        return fileURL
    }

    // MARK: - Auto Backup (once per day)

    func performAutoBackupIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        let lastBackup = defaults.object(forKey: lastBackupKey) as? Date

        if let lastBackup, Calendar.current.isDateInToday(lastBackup) {
            return
        }

        do {
            _ = try exportBackup(context: context)
            defaults.set(Date(), forKey: lastBackupKey)
            cleanupOldBackups()
        } catch {
            print("Auto backup failed: \(error)")
        }
    }

    // MARK: - Import

    func importBackup(from url: URL, context: ModelContext) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let jsonData = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: jsonData)

        // Delete existing data
        try context.delete(model: Item.self)
        try context.delete(model: FoodEntry.self)
        try context.delete(model: SavedName.self)
        try context.delete(model: DineInEntry.self)
        try context.delete(model: FastingEntry.self)
        try context.delete(model: FastingDebt.self)
        // Restore items
        for item in backup.items {
            let status = ItemStatus(rawValue: item.status) ?? .available
            let type = item.type.flatMap { GroceryType(rawValue: $0) } ?? .main
            let restored = Item(name: item.name, status: status, type: type)
            restored.createdAt = item.createdAt
            context.insert(restored)
        }

        for entry in backup.foodEntries {
            let restored = FoodEntry(name: entry.name, amount: entry.amount, createdAt: entry.createdAt)
            context.insert(restored)
        }

        for name in backup.savedNames {
            let restored = SavedName(value: name.value, lastUsed: name.lastUsed)
            context.insert(restored)
        }

        for entry in backup.dineInEntries {
            let restored = DineInEntry(name: entry.name, createdAt: entry.createdAt)
            context.insert(restored)
        }

        for entry in backup.fastingEntries {
            let restored = FastingEntry(startHour: entry.startHour, startMinute: entry.startMinute, durationMinutes: entry.durationMinutes, createdAt: entry.createdAt)
            restored.activeStartDate = entry.activeStartDate
            context.insert(restored)
        }

        for debt in backup.fastingDebts {
            let restored = FastingDebt(missedMinutes: debt.missedMinutes, createdAt: debt.createdAt)
            context.insert(restored)
        }

        try context.save()
    }

    // MARK: - List Backups

    func listBackups() -> [BackupFile] {
        let backupDir = backupDirectory()
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> BackupFile? in
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                let date = attributes?[.modificationDate] as? Date ?? Date.distantPast
                return BackupFile(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Cleanup

    /// Keep only the last 7 backups
    private func cleanupOldBackups() {
        let backups = listBackups()
        guard backups.count > 7 else { return }
        let toDelete = backups.dropFirst(7)
        for backup in toDelete {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }

    // MARK: - Private

    private func buildBackupData(context: ModelContext) throws -> BackupData {
        let items = try context.fetch(FetchDescriptor<Item>())
        let foodEntries = try context.fetch(FetchDescriptor<FoodEntry>())
        let savedNames = try context.fetch(FetchDescriptor<SavedName>())
        let dineInEntries = try context.fetch(FetchDescriptor<DineInEntry>())
        let fastingEntries = try context.fetch(FetchDescriptor<FastingEntry>())
        let fastingDebts = try context.fetch(FetchDescriptor<FastingDebt>())
        return BackupData(
            items: items.map { ItemBackup(name: $0.name, status: $0.status.rawValue, type: $0.groceryType.rawValue, createdAt: $0.createdAt) },
            foodEntries: foodEntries.map { FoodEntryBackup(name: $0.name, amount: $0.amount, createdAt: $0.createdAt) },
            savedNames: savedNames.map { SavedNameBackup(value: $0.value, lastUsed: $0.lastUsed) },
            dineInEntries: dineInEntries.map { DineInEntryBackup(name: $0.name, createdAt: $0.createdAt) },
            fastingEntries: fastingEntries.map {
                FastingEntryBackup(startHour: $0.startHour, startMinute: $0.startMinute, durationMinutes: $0.durationMinutes, activeStartDate: $0.activeStartDate, createdAt: $0.createdAt)
            },
            fastingDebts: fastingDebts.map { FastingDebtBackup(missedMinutes: $0.missedMinutes, createdAt: $0.createdAt) },
            backupDate: Date()
        )
    }
}

struct BackupFile: Identifiable {
    let url: URL
    let date: Date
    var id: URL { url }

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum BackupError: LocalizedError {
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportFailed(let message):
            return message
        }
    }
}
