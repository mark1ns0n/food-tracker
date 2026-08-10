//
//  SavedName.swift
//  foodtracker
//
//  Created by Codex on 09.02.2026.
//

import Foundation
import SwiftData

@Model
final class SavedName {
    /// Stable identity for sync (F01.02) — see `Item.id`.
    var id: UUID = UUID()
    var value: String
    var lastUsed: Date

    init(value: String, lastUsed: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.value = value
        self.lastUsed = lastUsed
    }
}
