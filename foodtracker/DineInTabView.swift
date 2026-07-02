//
//  DineInTabView.swift
//  foodtracker
//
//  Created by Codex on 25.01.2026.
//

import SwiftUI
import SwiftData

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
