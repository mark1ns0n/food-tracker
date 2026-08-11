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
    /// Stable identity for sync (F01.02); `ft.*` entity and event ids are
    /// derived from it (F01.06).
    ///
    /// The default makes SwiftData's migration additive, but **not** per row:
    /// it evaluates `UUID()` once and stamps that one value across the whole
    /// column, so every row carried over from before F01.02 shares an id. The
    /// owner's phone proved it on 2026-08-11. `FTBackfillService` hands out
    /// distinct ids before it reads any of them — see
    /// `makeRowIdentitiesDistinct()`, which is the only thing standing between
    /// a legacy store and thirteen groceries collapsing into one entity.
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
