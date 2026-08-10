//
//  FoodTabView.swift
//  foodtracker
//
//  Created by Claude on 04.03.2026.
//

import OSLog
import SwiftUI
import SwiftData

struct FoodTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ftWriter) private var writer

    // Groceries
    @Query(sort: \Item.createdAt) private var items: [Item]
    @State private var showAddGroceryDialog = false
    @State private var newGroceryName = ""
    @State private var newGroceryType: GroceryType = .main
    @State private var showCompletionNotification = false
    @State private var completionMessage: String = ""
    @State private var editingItem: Item?
    @State private var editGroceryName = ""
    @State private var editGroceryType: GroceryType = .main


    // Delivery
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var foodEntries: [FoodEntry]
    @Query(sort: \SavedName.lastUsed, order: .reverse) private var savedNames: [SavedName]
    @State private var showAddDeliveryDialog = false

    // Dine-In
    @Query(sort: \DineInEntry.createdAt, order: .reverse) private var dineInEntries: [DineInEntry]
    @State private var showAddDineInDialog = false

    // Accordion state
    @State private var groceriesExpanded = true
    @State private var deliveryExpanded = false
    @State private var dineInExpanded = false

    // MARK: - Computed

    private func availableGroceries(of type: GroceryType) -> [Item] {
        items.filter { $0.groceryType == type && $0.status == .available }
    }

    private func usedGroceries(of type: GroceryType) -> [Item] {
        items.filter { $0.groceryType == type && $0.status == .used }
    }

    private func items(of type: GroceryType) -> [Item] {
        items.filter { $0.groceryType == type }
    }

    private var activeDeliveryEntries: [FoodEntry] {
        foodEntries.filter { !$0.isExpired }
    }

    private var totalDeliveryAmount: Double {
        activeDeliveryEntries.reduce(0) { $0 + $1.amount }
    }

    private var activeDineInEntries: [DineInEntry] {
        dineInEntries.filter { !$0.isExpired }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    // MARK: Groceries
                    Section {
                        if groceriesExpanded {
                            if items.isEmpty {
                                Text("No groceries yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(GroceryType.allCases) { type in
                                    let typeItems = items(of: type)
                                    if !typeItems.isEmpty {
                                        Text(type.rawValue)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 4)

                                        ForEach(availableGroceries(of: type)) { item in
                                            ItemRow(item: item, onToggle: {
                                                toggleGroceryStatus(item)
                                            }, onDelete: {
                                                deleteGrocery(item)
                                            }, onEdit: {
                                                startEditing(item)
                                            })
                                        }

                                        ForEach(usedGroceries(of: type)) { item in
                                            ItemRow(item: item, onToggle: {
                                                toggleGroceryStatus(item)
                                            }, onDelete: {
                                                deleteGrocery(item)
                                            }, onEdit: {
                                                startEditing(item)
                                            })
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        AccordionHeader(
                            title: "Groceries",
                            systemImage: "list.bullet",
                            isExpanded: $groceriesExpanded,
                            onAdd: { showAddGroceryDialog = true },
                            onRefresh: refreshFullyUsedTypes
                        )
                    }

                    // MARK: Delivery
                    Section {
                        if deliveryExpanded {
                            if activeDeliveryEntries.isEmpty {
                                Text("No delivery entries yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                HStack {
                                    Spacer()
                                    TotalBadge(totalAmount: totalDeliveryAmount)
                                }
                                .listRowSeparator(.hidden)

                                ForEach(activeDeliveryEntries) { entry in
                                    FoodEntryRow(entry: entry)
                                }
                            }
                        }
                    } header: {
                        AccordionHeader(
                            title: "Delivery",
                            systemImage: "figure.outdoor.cycle",
                            isExpanded: $deliveryExpanded,
                            summary: activeDeliveryEntries.isEmpty ? nil : "(\(activeDeliveryEntries.count)) \(String(format: "%.1f", totalDeliveryAmount)) KD",
                            onAdd: { showAddDeliveryDialog = true }
                        )
                    }

                    // MARK: Dine-In
                    Section {
                        if dineInExpanded {
                            if activeDineInEntries.isEmpty {
                                Text("No dine-in entries yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(activeDineInEntries) { entry in
                                    DineInEntryRow(entry: entry)
                                }
                            }
                        }
                    } header: {
                        AccordionHeader(
                            title: "Dine-In",
                            systemImage: "fork.knife",
                            isExpanded: $dineInExpanded,
                            summary: activeDineInEntries.isEmpty ? nil : "(\(activeDineInEntries.count))",
                            onAdd: { showAddDineInDialog = true }
                        )
                    }

                }
                .listStyle(.sidebar)

                if showCompletionNotification {
                    NotificationOverlay(message: completionMessage)
                }
            }
            .sheet(isPresented: $showAddGroceryDialog) {
                AddItemDialog(
                    isPresented: $showAddGroceryDialog,
                    itemName: $newGroceryName,
                    itemType: $newGroceryType,
                    onApply: addNewGrocery
                )
            }
            .sheet(item: $editingItem) { item in
                EditItemDialog(
                    itemName: $editGroceryName,
                    itemType: $editGroceryType,
                    onCancel: { editingItem = nil },
                    onApply: {
                        applyEdit(to: item)
                        editingItem = nil
                    }
                )
            }
            .sheet(isPresented: $showAddDeliveryDialog) {
                FoodEntryDialog(
                    isPresented: $showAddDeliveryDialog,
                    savedNames: savedNames,
                    onAdd: { name, amount in handleAddDeliveryEntry(name: name, amount: amount) },
                    onSaveName: { name in saveName(name) }
                )
            }
            .sheet(isPresented: $showAddDineInDialog) {
                DineInAddDialog(
                    isPresented: $showAddDineInDialog,
                    savedNames: savedNames,
                    onAdd: { name in handleAddDineInEntry(name: name) },
                    onSaveName: { name in saveName(name) }
                )
            }
        }
    }

    // MARK: - Groceries Logic

    private func addNewGrocery() {
        guard !newGroceryName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation {
            write { try $0.addGrocery(name: newGroceryName, type: newGroceryType) }
            newGroceryName = ""
        }
    }

    private func toggleGroceryStatus(_ item: Item) {
        let type = item.groceryType
        withAnimation {
            write { try $0.toggleGrocery(id: item.id) }
        }
        checkIfAllGroceriesUsed(in: type)
    }

    private func resetGroceries(in type: GroceryType) {
        withAnimation {
            write { try $0.resetGroceries(ids: items(of: type).map(\.id)) }
        }
    }

    private func checkIfAllGroceriesUsed(in type: GroceryType) {
        let typeItems = items(of: type)
        if availableGroceries(of: type).isEmpty && !typeItems.isEmpty {
            completionMessage = "\(type.rawValue) готово"
            showCompletionNotification = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                resetGroceries(in: type)
                showCompletionNotification = false
            }
        }
    }

    private func deleteGrocery(_ item: Item) {
        withAnimation {
            write { try $0.deleteGrocery(id: item.id) }
        }
    }

    private func startEditing(_ item: Item) {
        editGroceryName = item.name
        editGroceryType = item.groceryType
        editingItem = item
    }

    private func refreshFullyUsedTypes() {
        // One call, so the whole refresh is one transaction in the log rather
        // than one per type.
        let ids = GroceryType.allCases.flatMap { type -> [UUID] in
            let typeItems = items(of: type)
            guard !typeItems.isEmpty, availableGroceries(of: type).isEmpty else { return [] }
            return typeItems.map(\.id)
        }
        guard !ids.isEmpty else { return }
        withAnimation {
            write { try $0.resetGroceries(ids: ids) }
        }
    }

    private func applyEdit(to item: Item) {
        let trimmed = editGroceryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            write { try $0.editGrocery(id: item.id, name: trimmed, type: editGroceryType) }
        }
    }

    /// Runs a mutation through the writer, or not at all.
    ///
    /// A failure to append leaves the tables exactly as they were — the writer
    /// projects only what the log accepted — so the message is the whole of the
    /// feedback: the row on screen is still the truth.
    private func write(_ mutation: (FTWriter) throws -> Void) {
        guard let writer else {
            // No writer means no log (a preview). Showing the data without
            // being able to record a change is better than changing a row the
            // log will never mention.
            return
        }
        do {
            try mutation(writer)
        } catch {
            Logger(subsystem: FTSyncComposition.applicationIdentifier, category: "Sync")
                .error("Could not record the change: \(String(describing: error))")
            completionMessage = "Не удалось сохранить"
            showCompletionNotification = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showCompletionNotification = false
            }
        }
    }

    // MARK: - Delivery Logic

    // Expiry is a *view* rule, not a deletion (F01.03): a row older than 30 days
    // drops out of `activeDeliveryEntries` on its own. Deleting it on appear
    // destroyed history no one asked to lose, and once the log is the source of
    // truth (F01.11) a local delete would have to travel as a real tombstone —
    // saying "this never happened" about a delivery that did.

    private func handleAddDeliveryEntry(name: String, amount: Double) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Name is required." }
        guard amount > 0 else { return "Amount must be greater than zero." }

        let normalizedName = trimmedName.lowercased()

        let activeDineIn = dineInEntries.filter { !$0.isExpired }
        let isInDineIn = activeDineIn.contains { $0.name.lowercased() == normalizedName }
        guard !isInDineIn else {
            return "Cannot order delivery from this restaurant - you dined in there recently."
        }

        let allowsMultiple = normalizedName == "talabat mart"
        let duplicate = activeDeliveryEntries.contains { $0.name.lowercased() == normalizedName }
        guard !duplicate || allowsMultiple else { return "That name is already in the list." }

        let entry = FoodEntry(name: trimmedName, amount: amount)
        modelContext.insert(entry)
        saveName(trimmedName)
        return nil
    }

    // MARK: - Dine-In Logic

    private func handleAddDineInEntry(name: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Name is required." }

        let normalizedName = trimmedName.lowercased()

        let duplicateInDineIn = activeDineInEntries.contains { $0.name.lowercased() == normalizedName }
        guard !duplicateInDineIn else { return "That restaurant is already in the Dine-In list." }

        let entry = DineInEntry(name: trimmedName)
        modelContext.insert(entry)
        saveName(trimmedName)

        let activeFoodEntries = foodEntries.filter { !$0.isExpired }
        let existsInDelivery = activeFoodEntries.contains { $0.name.lowercased() == normalizedName }
        if !existsInDelivery {
            let foodEntry = FoodEntry(name: trimmedName, amount: 0)
            modelContext.insert(foodEntry)
        }

        return nil
    }

    // MARK: - Shared

    @discardableResult
    private func saveName(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return "Name cannot be empty." }

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

// MARK: - Accordion Header

struct AccordionHeader: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    var summary: String? = nil
    let onAdd: () -> Void
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        HStack {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.title2)
                    Text(title)
                        .font(.title2.weight(.semibold))
                    if let summary {
                        Text(summary)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .textCase(nil)
    }
}

