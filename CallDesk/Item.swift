//
//  Item.swift
//  CallDesk
//
//  Created by 何玮 on 2026/7/30.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
