//
//  FoodTrackerTabView.swift
//  foodtracker
//
//  Created by Codex on 09.02.2026.
//

import SwiftUI
import SwiftData

struct FoodEntryRow: View {
    let entry: FoodEntry

    private var formattedAmount: String {
        entry.amount.formatted(.number.precision(.fractionLength(0...2)))
    }

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
                Text(formattedAmount)
                    .font(.headline)
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
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
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
            .padding(8)
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
                    Button {
                        attemptSave()
                    } label: {
                        Image(systemName: "checkmark")
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
