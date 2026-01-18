//
//  FoodTrackerTabView.swift
//  foodtracker
//
//  Created by Codex on 09.02.2026.
//

import SwiftUI
import SwiftData

struct FoodTrackerTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var entries: [FoodEntry]
    @Query(sort: \SavedName.lastUsed, order: .reverse) private var savedNames: [SavedName]

    @State private var showAddDialog = false

    private var activeEntries: [FoodEntry] {
        entries.filter { !$0.isExpired }
    }

    private var totalAmount: Double {
        activeEntries.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                if activeEntries.isEmpty {
                    ContentUnavailableView("Nothing yet", systemImage: "bicycle", description: Text("Add your first entry to track amounts."))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(activeEntries) { entry in
                        FoodEntryRow(entry: entry)
                    }
                }
            }
            .navigationTitle("Food Tracker")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TotalBadge(totalAmount: totalAmount)
                    Button(action: { showAddDialog = true }) {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showAddDialog) {
                FoodEntryDialog(
                    isPresented: $showAddDialog,
                    savedNames: savedNames,
                    onAdd: { name, amount in handleAddEntry(name: name, amount: amount) },
                    onSaveName: { name in saveName(name) }
                )
            }
            .onAppear { pruneExpiredEntries() }
            .onChange(of: entries.count) { _ in pruneExpiredEntries() }
        }
    }

    private func pruneExpiredEntries() {
        let expiredEntries = entries.filter { $0.isExpired }
        guard !expiredEntries.isEmpty else { return }

        expiredEntries.forEach { modelContext.delete($0) }
    }

    private func handleAddEntry(name: String, amount: Double) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Name is required."
        }
        guard amount > 0 else {
            return "Amount must be greater than zero."
        }

        let normalizedName = trimmedName.lowercased()
        let allowsMultiple = normalizedName == "talabat mart"
        let duplicate = activeEntries.contains { $0.name.lowercased() == normalizedName }
        guard !duplicate || allowsMultiple else {
            return "That name is already in the list."
        }

        let entry = FoodEntry(name: trimmedName, amount: amount)
        modelContext.insert(entry)
        saveName(trimmedName)
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

struct FoodEntryRow: View {
    let entry: FoodEntry

    private var formattedAmount: String {
        entry.amount.formatted(.number.precision(.fractionLength(0...2)))
    }

    var body: some View {
        HStack {
            Text(entry.name)
                .font(.body)
                .lineLimit(1)
            Spacer()
            Text(formattedAmount)
                .font(.headline)
        }
        .padding(.vertical, 6)
    }
}

struct TotalBadge: View {
    let totalAmount: Double

    private var formatted: String {
        totalAmount.formatted(.number.precision(.fractionLength(0...2)))
    }

    var body: some View {
        Text("Total: \(formatted)")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
    }
}

struct FoodEntryDialog: View {
    @Binding var isPresented: Bool
    let savedNames: [SavedName]
    let onAdd: (String, Double) -> String?
    let onSaveName: (String) -> String?

    @State private var nameText = ""
    @State private var amountText = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case amount
    }

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
                Section("Name") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            TextField("Saved name or new name", text: $nameText)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                                .focused($focusedField, equals: .name)
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
                                                Image(systemName: "figure.outdoor.cycle")
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

                Section("Amount") {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Focus immediately to avoid keyboard delay when the sheet opens.
                DispatchQueue.main.async {
                    focusedField = .name
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
                    Button("Save") {
                        attemptSave()
                    }
                    .disabled(nameText.trimmingCharacters(in: .whitespaces).isEmpty || amountText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func attemptSave() {
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }

        let normalizedAmountText = amountText.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalizedAmountText) else {
            errorMessage = "Enter a valid number."
            return
        }
        guard amount > 0 else {
            errorMessage = "Amount must be greater than zero."
            return
        }

        errorMessage = onAdd(trimmedName, amount)
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
        amountText = ""
        errorMessage = nil
        focusedField = nil
    }
}
