//
//  CategoryRule.swift
//  FocusGuard
//

import Foundation
import SwiftData

enum MatchType: String, Codable, CaseIterable {
    case contains = "Contains"
    case exact = "Exact"
    case regex = "Regex"
}

@Model
final class CategoryRule {
    var id: UUID
    var pattern: String
    var matchTypeRaw: String
    
    var category: Category?
    
    init(id: UUID = UUID(), pattern: String, matchType: MatchType = .contains) {
        self.id = id
        self.pattern = pattern
        self.matchTypeRaw = matchType.rawValue
    }
    
    var matchType: MatchType {
        get { MatchType(rawValue: matchTypeRaw) ?? .contains }
        set { matchTypeRaw = newValue.rawValue }
    }
    
    func matches(_ text: String) -> Bool {
        switch matchType {
        case .contains:
            return text.localizedCaseInsensitiveContains(pattern)
        case .exact:
            return text.lowercased() == pattern.lowercased()
        case .regex:
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: text.utf16.count)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            }
            return false
        }
    }
}
