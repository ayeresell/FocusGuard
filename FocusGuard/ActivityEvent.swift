//
//  ActivityEvent.swift
//  FocusGuard
//

import Foundation
import SwiftData

@Model
final class ActivityEvent {
    var timestamp: Date
    var duration: TimeInterval
    var appName: String
    var windowTitle: String
    var bundleId: String?
    var isProductive: Bool?
    var productivityReason: String?
    
    var category: Category?
    
    init(timestamp: Date = Date(), duration: TimeInterval = 0, appName: String, bundleId: String? = nil, windowTitle: String = "", category: Category? = nil, isProductive: Bool? = nil, productivityReason: String? = nil) {
        self.timestamp = timestamp
        self.duration = duration
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.category = category
        self.isProductive = isProductive
        self.productivityReason = productivityReason
    }
}

extension TimeInterval {
    func formatHMS() -> String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return "\(hours)h \(minutes)m \(seconds)s"
    }
}