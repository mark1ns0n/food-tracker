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
    var name: String
    var status: ItemStatus
    var type: GroceryType?
    var createdAt: Date

    var groceryType: GroceryType {
        get { type ?? .main }
        set { type = newValue }
    }

    init(name: String, status: ItemStatus = .available, type: GroceryType = .main) {
        self.name = name
        self.status = status
        self.type = type
        self.createdAt = Date()
    }
}
