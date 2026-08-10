//
//  BackupView.swift
//  foodtracker
//
//  Created by Claude on 08.03.2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(\.modelContext) private var modelContext

    /// Once the backfill has run (F01.11), the event log stands behind the
    /// store, and a restore would wipe and rewrite the tables behind its back —
    /// the store and the log would disagree forever after. Import goes away;
    /// export stays, it only reads.
    @AppStorage(FTBackfillService.doneKey) private var backfillDone = false

    @State private var backups: [BackupFile] = []
    @State private var isExporting = false
    @State private var showImportConfirm = false
    @State private var showFileImporter = false
    @State private var selectedBackup: BackupFile?
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var shareItem: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        exportNow()
                    } label: {
                        Label("Backup Now", systemImage: "arrow.down.doc.fill")
                    }
                    .disabled(isExporting)
                } footer: {
                    Text("Auto-backup runs once a day when you open the app. Old backups (more than 7) are automatically deleted.")
                }

                Section {
                    if !backfillDone {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Import from File", systemImage: "square.and.arrow.down")
                        }
                    }
                } footer: {
                    Text(
                        backfillDone
                            ? "Import is turned off: this device's data has moved into the sync log, and restoring a backup would overwrite it. Backups remain available for export."
                            : "Import a backup JSON file from Files, AirDrop, or any other source."
                    )
                }

                Section("Local Backups") {
                    if backups.isEmpty {
                        Text("No backups yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(backups) { backup in
                            HStack {
                                Button {
                                    selectedBackup = backup
                                    showImportConfirm = true
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(backup.displayName)
                                            .foregroundStyle(.primary)
                                        Text(backup.url.lastPathComponent)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(backfillDone)

                                Spacer()

                                Button {
                                    shareItem = backup.url
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Backup")
            .onAppear {
                backups = BackupService.shared.listBackups()
            }
            .alert("Backup", isPresented: $showAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog(
                "Restore from backup?",
                isPresented: $showImportConfirm,
                titleVisibility: .visible
            ) {
                Button("Restore", role: .destructive) {
                    if let backup = selectedBackup {
                        restoreBackup(from: backup.url)
                    }
                }
                Button("Cancel", role: .cancel) {
                    selectedBackup = nil
                }
            } message: {
                Text("This will replace ALL current data with the backup. This cannot be undone.")
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        restoreBackup(from: url)
                    }
                case .failure(let error):
                    alertMessage = "Import failed: \(error.localizedDescription)"
                    showAlert = true
                }
            }
            .sheet(item: $shareItem) { url in
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func exportNow() {
        isExporting = true
        do {
            let url = try BackupService.shared.exportBackup(context: modelContext)
            alertMessage = "Backup saved:\n\(url.lastPathComponent)"
            backups = BackupService.shared.listBackups()
        } catch {
            alertMessage = "Backup failed: \(error.localizedDescription)"
        }
        isExporting = false
        showAlert = true
    }

    private func restoreBackup(from url: URL) {
        do {
            try BackupService.shared.importBackup(from: url, context: modelContext)
            alertMessage = "Data restored successfully"
        } catch {
            alertMessage = "Restore failed: \(error.localizedDescription)"
        }
        showAlert = true
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    BackupView()
        .modelContainer(for: [Item.self, FoodEntry.self, SavedName.self, DineInEntry.self,  FastingEntry.self, FastingDebt.self], inMemory: true)
}
