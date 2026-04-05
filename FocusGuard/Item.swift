//
//  Item.swift
//  FocusGuard
//
//  Created by Anton Guntsev on 5/4/26.
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
