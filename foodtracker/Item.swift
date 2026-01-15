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

@Model
final class Item {
    var name: String
    var status: ItemStatus
    var createdAt: Date
    
    init(name: String, status: ItemStatus = .available) {
        self.name = name
        self.status = status
        self.createdAt = Date()
    }
}
