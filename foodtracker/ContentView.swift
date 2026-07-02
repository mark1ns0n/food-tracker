//
//  ContentView.swift
//  foodtracker
//
//  Created by Ivan Markin on 15.01.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            FoodTabView()
                .tabItem {
                    Label("Food", systemImage: "fork.knife")
                }

            FastingTabView()
                .tabItem {
                    Label("Fasting", systemImage: "timer")
                }

            BackupView()
                .tabItem {
                    Label("Backup", systemImage: "arrow.triangle.2.circlepath")
                }
        }
    }
}

struct ItemRow: View {
    let item: Item
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack {
            Button(action: onEdit) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Spacer()
            
            Button(action: onToggle) {
                Image(systemName: item.status == .available ? "plus" : "checkmark")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(width: 20, height: 20)
                    .padding(8)
                    .background(item.status == .available ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.borderless)
            
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(width: 20, height: 20)
                    .padding(8)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Delete item?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(item.name)\"?")
        }
    }
}

struct AddItemDialog: View {
    @Binding var isPresented: Bool
    @Binding var itemName: String
    @Binding var itemType: GroceryType
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Name") {
                    TextField("Enter name", text: $itemName)
                }
                Section("Type") {
                    Picker("Type", selection: $itemType) {
                        ForEach(GroceryType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        itemName = ""
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply()
                        isPresented = false
                    }
                    .disabled(itemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct EditItemDialog: View {
    @Binding var itemName: String
    @Binding var itemType: GroceryType
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Name") {
                    TextField("Enter name", text: $itemName)
                }
                Section("Type") {
                    Picker("Type", selection: $itemType) {
                        ForEach(GroceryType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: onApply)
                        .disabled(itemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct NotificationOverlay: View {
    let message: String
    
    var body: some View {
        VStack {
            Text(message)
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(10)
                .padding()
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 50)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, FoodEntry.self, SavedName.self, DineInEntry.self, FastingEntry.self, FastingDebt.self], inMemory: true)
}
