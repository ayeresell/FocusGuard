//
//  ProductivityRule.swift
//  FocusGuard
//

import Foundation
import SwiftData

@Model
final class ProductivityRule {
    var id: UUID
    var appName: String
    var windowTitle: String
    var isProductive: Bool
    var reason: String
    
    init(id: UUID = UUID(), appName: String, windowTitle: String = "", isProductive: Bool, reason: String) {
        self.id = id
        self.appName = appName
        self.windowTitle = windowTitle
        self.isProductive = isProductive
        self.reason = reason
    }
}
