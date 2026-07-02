//
//  FoodTabView.swift
//  foodtracker
//
//  Created by Claude on 04.03.2026.
//

import SwiftUI
import SwiftData

struct FoodTabView: View {
    @Environment(\.modelContext) private var modelContext

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
            .onAppear {
                pruneExpiredDeliveryEntries()
                pruneExpiredDineInEntries()
            }
        }
    }

    // MARK: - Groceries Logic

    private func addNewGrocery() {
        guard !newGroceryName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation {
            let newItem = Item(name: newGroceryName, type: newGroceryType)
            modelContext.insert(newItem)
            newGroceryName = ""
        }
    }

    private func toggleGroceryStatus(_ item: Item) {
        let type = item.groceryType
        withAnimation {
            item.status = (item.status == .available) ? .used : .available
        }
        checkIfAllGroceriesUsed(in: type)
    }

    private func resetGroceries(in type: GroceryType) {
        withAnimation {
            for item in items(of: type) {
                item.status = .available
            }
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
            modelContext.delete(item)
        }
    }

    private func startEditing(_ item: Item) {
        editGroceryName = item.name
        editGroceryType = item.groceryType
        editingItem = item
    }

    private func refreshFullyUsedTypes() {
        withAnimation {
            for type in GroceryType.allCases {
                let typeItems = items(of: type)
                guard !typeItems.isEmpty,
                      availableGroceries(of: type).isEmpty else { continue }
                for item in typeItems {
                    item.status = .available
                }
            }
        }
    }

    private func applyEdit(to item: Item) {
        let trimmed = editGroceryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            item.name = trimmed
            item.type = editGroceryType
        }
    }

    // MARK: - Delivery Logic

    private func pruneExpiredDeliveryEntries() {
        let expired = foodEntries.filter { $0.isExpired }
        guard !expired.isEmpty else { return }
        expired.forEach { modelContext.delete($0) }
    }

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

    private func pruneExpiredDineInEntries() {
        let expired = dineInEntries.filter { $0.isExpired }
        guard !expired.isEmpty else { return }
        expired.forEach { modelContext.delete($0) }
    }

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

