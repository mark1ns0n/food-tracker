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
    var value: String
    var lastUsed: Date

    init(value: String, lastUsed: Date = Date()) {
        self.value = value
        self.lastUsed = lastUsed
    }
}
