//
//  Item.swift
//  foodtracker
//
//  Created by Ivan Markin on 15.01.2026.
//

import Foundation
import SwiftData

enum ItemStatus: String, Codable {
    case available
    case used
}

enum GroceryType: String, Codable, CaseIterable, Identifiable {
    case main = "Основа"
    case side = "Гарнир"
    case salad = "Салат"

    var id: String { rawValue }
}

@Model
final class Item {
    /// Stable identity for sync (F01.02). Defaulted so SwiftData applies a
    /// lightweight additive migration and existing rows get a fresh UUID on
    /// first open; `ft.*` event IDs are derived from it in F01.06.
    var id: UUID = UUID()
    var name: String
    var status: ItemStatus
    var type: GroceryType?
    var createdAt: Date

    var groceryType: GroceryType {
        get { type ?? .main }
        set { type = newValue }
    }

    init(
        name: String,
        status: ItemStatus = .available,
        type: GroceryType = .main,
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.type = type
        self.createdAt = Date()
    }
}
