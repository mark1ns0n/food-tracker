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
            SpinneysTabView()
                .tabItem {
                    Label("Spinneys", systemImage: "list.bullet")
                }
            
            Text("Will be implemented later")
                .tabItem {
                    Label("Tab 2", systemImage: "star")
                }
            
            Text("Will be implemented later")
                .tabItem {
                    Label("Tab 3", systemImage: "gear")
                }
        }
    }
}

struct SpinneysTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt) private var items: [Item]
    
    @State private var showAddDialog = false
    @State private var newItemName = ""
    @State private var showCompletionNotification = false
    
    var availableItems: [Item] {
        items.filter { $0.status == .available }
    }
    
    var usedItems: [Item] {
        items.filter { $0.status == .used }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    ForEach(availableItems) { item in
                        ItemRow(item: item, onToggle: {
                            toggleItemStatus(item)
                        })
                    }
                    
                    if !usedItems.isEmpty {
                        Section("Used") {
                            ForEach(usedItems) { item in
                                ItemRow(item: item, onToggle: {
                                    toggleItemStatus(item)
                                })
                            }
                        }
                    }
                }
                .navigationTitle("Spinneys")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showAddDialog = true }) {
                            Text("Add")
                        }
                    }
                }
                .sheet(isPresented: $showAddDialog) {
                    AddItemDialog(
                        isPresented: $showAddDialog,
                        itemName: $newItemName,
                        onApply: addNewItem
                    )
                }
                
                if showCompletionNotification {
                    NotificationOverlay(message: "you did that")
                }
            }
        }
    }
    
    private func addNewItem() {
        guard !newItemName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        withAnimation {
            let newItem = Item(name: newItemName)
            modelContext.insert(newItem)
            newItemName = ""
        }
    }
    
    private func toggleItemStatus(_ item: Item) {
        withAnimation {
            item.status = (item.status == .available) ? .used : .available
        }
        
        checkIfAllUsed()
    }
    
    private func checkIfAllUsed() {
        if availableItems.isEmpty && !items.isEmpty {
            // All items are used
            showCompletionNotification = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    for item in items {
                        item.status = .available
                    }
                    showCompletionNotification = false
                }
            }
        }
    }
}

struct ItemRow: View {
    let item: Item
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Text(item.name)
                .font(.body)
            
            Spacer()
            
            Button(action: onToggle) {
                Text(item.status == .available ? "Available" : "Used")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(item.status == .available ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddItemDialog: View {
    @Binding var isPresented: Bool
    @Binding var itemName: String
    let onApply: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Name") {
                    TextField("Enter name", text: $itemName)
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
        .modelContainer(for: Item.self, inMemory: true)
}
