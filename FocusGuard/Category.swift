//
//  Category.swift
//  FocusGuard
//

import Foundation
import SwiftData
import SwiftUI
import OSLog

@Model
final class Category {
    var id: UUID
    var name: String
    var colorHex: String
    
    @Relationship(deleteRule: .cascade, inverse: \CategoryRule.category)
    var rules: [CategoryRule]?
    
    @Relationship(deleteRule: .nullify, inverse: \ActivityEvent.category)
    var events: [ActivityEvent]?
    
    init(id: UUID = UUID(), name: String, colorHex: String = "#0000FF") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
    
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
    
    @MainActor
    static func seedDefaults(into context: ModelContext) {
        let defaults: [(name: String, hex: String, apps: [String])] = [
            ("Software Development", "#3498db", ["Xcode", "Code", "Terminal", "iTerm2", "IntelliJ IDEA", "Android Studio", "Cursor", "Ghostty"]),
            ("Communication & Chat", "#e74c3c", ["Slack", "Discord", "Telegram", "Messages", "WhatsApp", "Zoom", "Microsoft Teams", "Mail", "Spark"]),
            ("Web Browsing & Research", "#2ecc71", ["Safari", "Google Chrome", "Firefox", "Arc", "Brave Browser", "Microsoft Edge", "Opera"]),
            ("Entertainment & Media", "#9b59b6", ["Spotify", "Music", "Yandex Music", "IINA", "VLC", "Steam", "Podcasts", "TV"]),
            ("Productivity & Office", "#f1c40f", ["Notes", "Notion", "Obsidian", "Microsoft Word", "Microsoft Excel", "Pages", "Numbers", "Keynote", "Calendar", "Reminders"]),
            ("System & Utilities", "#95a5a6", ["Finder", "System Settings", "Activity Monitor", "1Password", "Raycast", "Alfred", "FocusGuard"]),
            ("Design & Creativity", "#e67e22", ["Figma", "Adobe Photoshop", "Adobe Illustrator", "Final Cut Pro", "Blender", "Lightroom"]),
            ("Other", "#bdc3c7", [])
        ]
        
        for def in defaults {
            let cat = Category(name: def.name, colorHex: def.hex)
            context.insert(cat)
            
            var rules: [CategoryRule] = []
            for app in def.apps {
                let rule = CategoryRule(pattern: app, matchType: .contains)
                rule.category = cat
                context.insert(rule)
                rules.append(rule)
            }
            cat.rules = rules
        }
        
        do {
            try context.save()
        } catch {
            Logger().error("FocusGuard: Failed to seed default categories: \(error.localizedDescription)")
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0

        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
}
