//
//  DineInTabView.swift
//  foodtracker
//
//  Created by Codex on 25.01.2026.
//

import SwiftUI
import SwiftData

struct DineInTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DineInEntry.createdAt, order: .reverse) private var dineInEntries: [DineInEntry]
    @Query(sort: \SavedName.lastUsed, order: .reverse) private var savedNames: [SavedName]
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var foodEntries: [FoodEntry]

    @State private var showAddDialog = false

    private var activeEntries: [DineInEntry] {
        dineInEntries.filter { !$0.isExpired }
    }

    var body: some View {
        NavigationStack {
            List {
                if activeEntries.isEmpty {
                    ContentUnavailableView("No Dine-In entries", systemImage: "fork.knife", description: Text("Add your first dine-in restaurant."))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(activeEntries) { entry in
                        DineInEntryRow(entry: entry)
                    }
                }
            }
            .navigationTitle("Dine-In")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddDialog = true }) {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showAddDialog) {
                DineInAddDialog(
                    isPresented: $showAddDialog,
                    savedNames: savedNames,
                    onAdd: { name in handleAddEntry(name: name) },
                    onSaveName: { name in saveName(name) }
                )
            }
            .onAppear { pruneExpiredEntries() }
            .onChange(of: dineInEntries.count) { pruneExpiredEntries() }
        }
    }

    private func pruneExpiredEntries() {
        let expiredEntries = dineInEntries.filter { $0.isExpired }
        guard !expiredEntries.isEmpty else { return }

        expiredEntries.forEach { modelContext.delete($0) }
    }

    private func handleAddEntry(name: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Name is required."
        }

        let normalizedName = trimmedName.lowercased()
        
        // Check if already exists in DineIn list (ONLY check Dine-In, not Delivery)
        let duplicateInDineIn = activeEntries.contains { $0.name.lowercased() == normalizedName }
        guard !duplicateInDineIn else {
            return "That restaurant is already in the Dine-In list."
        }

        // Add to DineIn first
        let entry = DineInEntry(name: trimmedName)
        modelContext.insert(entry)
        saveName(trimmedName)

        // Check if restaurant exists in Delivery (FoodEntry) list
        let activeFoodEntries = foodEntries.filter { !$0.isExpired }
        let existsInDelivery = activeFoodEntries.contains { $0.name.lowercased() == normalizedName }
        
        // If not in Delivery, add it with amount = 0 to block future delivery ordering
        if !existsInDelivery {
            let foodEntry = FoodEntry(name: trimmedName, amount: 0)
            modelContext.insert(foodEntry)
        }

        return nil
    }

    @discardableResult
    private func saveName(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return "Name cannot be empty."
        }

        let normalized = trimmedValue.lowercased()
        if let existing = savedNames.first(where: { $0.value.lowercased() == normalized }) {
            existing.lastUsed = Date()
            return nil
        }

        let newName = SavedName(value: trimmedValue)
        modelContext.insert(newName)
        return nil
    }
}

struct DineInEntryRow: View {
    let entry: DineInEntry

    private var formattedCreatedAt: String {
        entry.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var daysRemainingText: String {
        "\(entry.daysRemaining) day\(entry.daysRemaining == 1 ? "" : "s") left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
            }

            HStack {
                Label(formattedCreatedAt, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(daysRemainingText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 6)
    }
}

struct DineInAddDialog: View {
    @Binding var isPresented: Bool
    let savedNames: [SavedName]
    let onAdd: (String) -> String?
    let onSaveName: (String) -> String?

    @State private var nameText = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Bool

    private var filteredNames: [SavedName] {
        guard !nameText.isEmpty else { return savedNames }
        return savedNames.filter { $0.value.localizedCaseInsensitiveContains(nameText) }
    }

    private var canAddCurrentToSaved: Bool {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !savedNames.contains { $0.value.lowercased() == trimmed.lowercased() }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Restaurant Name") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            TextField("Saved name or new name", text: $nameText)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                                .focused($focusedField)
                            Button {
                                addCurrentToSaved()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .disabled(!canAddCurrentToSaved)
                            .foregroundStyle(canAddCurrentToSaved ? Color.accentColor : Color.secondary)
                        }

                        if !filteredNames.isEmpty {
                            Text("Suggestions")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(filteredNames) { suggestion in
                                        Button {
                                            nameText = suggestion.value
                                        } label: {
                                            HStack {
                                                Image(systemName: "fork.knife")
                                                Text(suggestion.value)
                                                Spacer()
                                                if suggestion.value.caseInsensitiveCompare(nameText) == .orderedSame {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(Color.accentColor)
                                                }
                                            }
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            .frame(maxHeight: 160)
                        } else {
                            Text("No saved names yet")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(.secondary.opacity(0.3))
                            Text("or")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(.secondary.opacity(0.3))
                        }
                        Text("Type a new name or tap a suggestion. Use + to remember a new option.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Dine-In")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                DispatchQueue.main.async {
                    focusedField = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        resetFields()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        attemptAdd()
                    }
                    .disabled(nameText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func attemptAdd() {
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }

        errorMessage = onAdd(trimmedName)
        guard errorMessage == nil else { return }

        resetFields()
        isPresented = false
    }

    private func addCurrentToSaved() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = onSaveName(trimmed)
    }

    private func resetFields() {
        nameText = ""
        errorMessage = nil
        focusedField = false
    }
}
