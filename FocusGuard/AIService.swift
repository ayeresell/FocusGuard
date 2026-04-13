//
//  AIService.swift
//  FocusGuard
//

import Foundation
import SwiftData
import SwiftUI
import OSLog

struct AICategoryMatch: Codable {
    let appName: String
    let categoryName: String
}

struct AICategorizationResponse: Codable {
    let matches: [AICategoryMatch]
}

struct AIProductivityMatch: Codable {
    let appName: String
    let windowTitle: String
    let isProductive: Bool
    let reason: String
}

struct AIProductivityResponse: Codable {
    let matches: [AIProductivityMatch]
}

@MainActor
@Observable
class AIService {
    var isProcessingCategories = false
    var isProcessingInsights = false
    var isProcessingProductivity = false
    var lastSummary = ""
    
    var apiKey: String {
        KeychainHelper.load(key: "gemini_api_key") ?? ""
    }
    
    var shareWindowTitles: Bool {
        UserDefaults.standard.bool(forKey: "ai_share_window_titles")
    }
    
    var isPro: Bool {
        UserDefaults.standard.bool(forKey: "isPro")
    }
    
    // MARK: - Feature A: Categorize Unknown Apps
    func categorizeUnknownApps(context: ModelContext, events: [ActivityEvent]) async {
        guard isPro && !apiKey.isEmpty else { return }
        
        isProcessingCategories = true
        defer { isProcessingCategories = false }
        
        // Extract unique app names that currently have no category
        var unknownApps = Set<String>()
        for event in events where event.category == nil {
            unknownApps.insert(event.appName)
        }
        
        guard !unknownApps.isEmpty else { return }
        let appsList = unknownApps.joined(separator: ", ")
        
        let systemPrompt = """
        You are a Mac app categorization assistant.
        Assign each app in the list to exactly ONE of these categories:
        - "Software Development"
        - "Communication & Chat"
        - "Web Browsing & Research"
        - "Entertainment & Media"
        - "Productivity & Office"
        - "System & Utilities"
        - "Design & Creativity"
        - "Other"
        
        Return ONLY a JSON object:
        {
          "matches": [
            { "appName": "Exact Name From List", "categoryName": "Assigned Category" }
          ]
        }
        """
        
        guard let data = await callGemini(systemPrompt: systemPrompt, userMessage: "Apps to categorize: \(appsList)") else { return }
        
        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(AICategorizationResponse.self, from: data)
            applyNewCategories(matches: result.matches, context: context, allEvents: events)
        } catch {
            Logger().error("Failed to parse AI categorization: \(error.localizedDescription)")
        }
    }
    
    private func applyNewCategories(matches: [AICategoryMatch], context: ModelContext, allEvents: [ActivityEvent]) {
        let descriptor = FetchDescriptor<Category>()
        let existingCategories = (try? context.fetch(descriptor)) ?? []
        
        for match in matches {
            guard let category = existingCategories.first(where: { $0.name.lowercased() == match.categoryName.lowercased() }) else { continue }
            
            // Create a rule for this app
            if !(category.rules?.contains(where: { $0.pattern == match.appName }) ?? false) {
                let rule = CategoryRule(pattern: match.appName, matchType: .contains)
                rule.category = category
                context.insert(rule)
                if category.rules == nil { category.rules = [] }
                category.rules?.append(rule)
            }
            
            // Retroactively apply to events
            for event in allEvents where event.category == nil && event.appName == match.appName {
                event.category = category
            }
        }
        
        do {
            try context.save()
        } catch {
            Logger().error("FocusGuard: Failed to save categorization results: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: NSNotification.Name("RulesDidUpdate"), object: nil)
    }

    // MARK: - Feature B: Analyze Productivity (Subscription Only)
    func analyzeProductivity(context: ModelContext, events: [ActivityEvent]) async {
        guard isPro && !apiKey.isEmpty else { return }
        
        isProcessingProductivity = true
        defer { isProcessingProductivity = false }
        
        // Identify unique combinations of app name and window title that haven't been analyzed yet
        var uniqueCombos = Set<String>()
        var listToAnalyze: [[String: String]] = []
        
        for event in events where event.isProductive == nil {
            let comboKey = "\(event.appName)|\(event.windowTitle)"
            if !uniqueCombos.contains(comboKey) {
                uniqueCombos.insert(comboKey)
                listToAnalyze.append(["appName": event.appName, "windowTitle": event.windowTitle])
            }
        }
        
        guard !listToAnalyze.isEmpty else { return }
        
        // Process in batches of 30
        let batchSize = 30
        for i in stride(from: 0, to: listToAnalyze.count, by: batchSize) {
            let end = min(i + batchSize, listToAnalyze.count)
            let batch = Array(listToAnalyze[i..<end])
            
            guard let jsonBatch = try? JSONEncoder().encode(batch),
                  let batchString = String(data: jsonBatch, encoding: .utf8),
                  !batchString.isEmpty else {
                Logger().error("FocusGuard: Failed to encode productivity batch for AI analysis")
                continue
            }

            let systemPrompt = """
            You are a productivity expert. For each item in the list (app name and window title), determine if the activity is "productive" or "unproductive".
            
            Special Rules:
            - If window title is missing or generic (like "zsh", "bash", "Ready"), judge based on the app name.
            - Terminal/Xcode/Cursor are usually Productive unless the title explicitly shows something else.
            - Focus on the intent of the activity.
            
            Return ONLY a JSON object:
            {
              "matches": [
                { "appName": "...", "windowTitle": "...", "isProductive": true/false, "reason": "Short justification" }
              ]
            }
            """
            
            guard let data = await callGemini(systemPrompt: systemPrompt, userMessage: "Analyze these activities:\n\(batchString)") else { continue }
            
            do {
                let result = try JSONDecoder().decode(AIProductivityResponse.self, from: data)
                applyProductivityResults(matches: result.matches, context: context, allEvents: events)
            } catch {
                Logger().error("Failed to parse AI productivity: \(error.localizedDescription)")
            }
            
            // Add a small delay between batches to avoid rate limits
            if end < listToAnalyze.count {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    
    private func applyProductivityResults(matches: [AIProductivityMatch], context: ModelContext, allEvents: [ActivityEvent]) {
        for match in matches {
            let targetApp = match.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetTitle = match.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Save as a permanent rule
            let rule = ProductivityRule(appName: targetApp, windowTitle: targetTitle, isProductive: match.isProductive, reason: match.reason)
            context.insert(rule)
            
            let targetAppLower = targetApp.lowercased()
            let targetTitleLower = targetTitle.lowercased()
            
            for event in allEvents {
                let eventApp = event.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let eventTitle = event.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                
                if eventApp == targetAppLower {
                    // Precise match: titles match exactly
                    if eventTitle == targetTitleLower {
                        event.isProductive = match.isProductive
                        event.productivityReason = match.reason
                    } 
                    // Fallback match: only if event has NO title and AI result has NO title
                    else if eventTitle.isEmpty && (targetTitleLower.isEmpty || targetTitleLower == "none") {
                        event.isProductive = match.isProductive
                        event.productivityReason = match.reason
                    }
                }
            }
        }
        do {
            try context.save()
        } catch {
            Logger().error("FocusGuard: Failed to save productivity results: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: NSNotification.Name("RulesDidUpdate"), object: nil)
    }

    // MARK: - Feature C: Generate Daily Insights
    func generateDailyInsights(events: [ActivityEvent]) async {
        guard isPro && !apiKey.isEmpty else {
            self.lastSummary = isPro ? "API Key is missing. Please set it in Settings." : "AI Insights requires Pro subscription."
            return
        }
        
        isProcessingInsights = true
        defer { isProcessingInsights = false }
        
        // Group data
        var usageDict: [String: TimeInterval] = [:]
        for event in events {
            if event.duration <= 0 { continue }
            let key = shareWindowTitles && !event.windowTitle.isEmpty ? "\(event.appName) (\(event.windowTitle))" : event.appName
            usageDict[key, default: 0] += event.duration
        }
        
        let sortedUsage = usageDict.sorted { $0.value > $1.value }.prefix(20) // Top 20 items
        var usageText = ""
        for (item, duration) in sortedUsage {
            let mins = Int(duration / 60)
            if mins > 0 {
                usageText += "- \(item): \(mins) mins\n"
            }
        }
        
        if usageText.isEmpty {
            self.lastSummary = "Not enough data to generate insights yet."
            return
        }
        
        let systemPrompt = """
        You are a productivity coach analyzing a user's daily Mac usage.
        Based on the provided top usage data, write a concise, encouraging 2-3 sentence summary of how they spent their time.
        Highlight what they focused on, any potential distractions, and keep the tone professional but friendly.
        Do not use JSON, just return plain text.
        """
        
        guard let data = await callGemini(systemPrompt: systemPrompt, userMessage: "Usage Data:\n\(usageText)") else {
            self.lastSummary = "Failed to reach AI service."
            return
        }
        
        self.lastSummary = String(data: data, encoding: .utf8) ?? "Failed to parse text."
    }
    
    // MARK: - API Helper
    private func callGemini(systemPrompt: String, userMessage: String) async -> Data? {
        let requestBody: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["parts": [["text": userMessage]]]],
            "generationConfig": ["responseMimeType": systemPrompt.contains("JSON") ? "application/json" : "text/plain"]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody),
              let apiUrl = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else { return nil }
        
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                Logger().error("FocusGuard: Gemini API error HTTP \(httpResponse.statusCode)")
                return nil
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let contentObj = firstCandidate["content"] as? [String: Any],
               let parts = contentObj["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text.data(using: .utf8)
            }
        } catch {
            return nil
        }
        return nil
    }
}
