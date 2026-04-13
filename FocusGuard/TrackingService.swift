//
//  TrackingService.swift
//  FocusGuard
//

import Foundation
import AppKit
import SwiftData
import OSLog
import SwiftUI
import Observation
import ApplicationServices

@MainActor
@Observable
class TrackingService {
    var now: Date = Date()
    var hasAccessibilityPermission: Bool = false
    
    @ObservationIgnored private var modelContext: ModelContext
    @ObservationIgnored private var workspace = NSWorkspace.shared
    @ObservationIgnored private var trackingTimer: Timer?
    @ObservationIgnored private var currentEvent: ActivityEvent?
    @ObservationIgnored private var emptyTitleBufferStart: Date?
    @ObservationIgnored private var lastCleanupDate: Date?
    
    @ObservationIgnored private var cachedCategories: [Category] = []
    @ObservationIgnored private var cachedProductivityRules: [ProductivityRule] = []
    @ObservationIgnored private var rulesObserver: NSObjectProtocol?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.hasAccessibilityPermission = AXIsProcessTrusted()
        seedCategoriesIfNeeded()
        refreshCaches()
        startTracking()

        rulesObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name("RulesDidUpdate"), object: nil, queue: .main) { [weak self] _ in
            self?.refreshCaches()
        }
    }
    
    private func seedCategoriesIfNeeded() {
        let descriptor = FetchDescriptor<Category>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        if count == 0 {
            Category.seedDefaults(into: modelContext)
        }
    }
    
    func refreshCaches() {
        cachedCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        cachedProductivityRules = (try? modelContext.fetch(FetchDescriptor<ProductivityRule>())) ?? []
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            Logger().error("FocusGuard: Failed to save context: \(error.localizedDescription)")
        }
    }
    
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }
    
    private func startTracking() {
        closeAllOpenEventsOnStartup()
        cleanupOldEvents()
        
        // Single unified timer for the entire app. 
        // 0.5s is a good balance between instant feedback and low CPU usage.
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let currentDate = Date()
                self.now = currentDate
                self.pollActiveWindow()
                
                // Run cleanup if a day has passed since last cleanup
                if let last = self.lastCleanupDate, !Calendar.current.isDateInToday(last) {
                    self.cleanupOldEvents()
                }
            }
        }
        
        // Listen for instant app switching events
        workspace.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                self?.pollActiveWindow()
            }
        }
        
        pollActiveWindow()
    }
    
    private func cleanupOldEvents() {
        lastCleanupDate = Date()
        let calendar = Calendar.current
        
        // Retain 8 days of history to fully support the "This Week" (7 days) view without cutting off the edge.
        guard let cutoffDate = calendar.date(byAdding: .day, value: -8, to: Date()) else { return }
        let startOfCutoff = calendar.startOfDay(for: cutoffDate)
        
        let descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.timestamp < startOfCutoff })
        
        if let oldEvents = try? modelContext.fetch(descriptor), !oldEvents.isEmpty {
            for event in oldEvents {
                modelContext.delete(event)
            }
            saveContext()
            Logger().info("Cleaned up \(oldEvents.count) old tracking events.")
        }
    }
    
    private func closeAllOpenEventsOnStartup() {
        let now = Date()
        let descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.duration == 0 })
        if let openEvents = try? modelContext.fetch(descriptor) {
            for event in openEvents {
                let duration = now.timeIntervalSince(event.timestamp)
                if duration > 3600 * 12 { // 12 hours max
                    event.duration = 60 
                } else {
                    event.duration = max(1.0, duration)
                }
            }
        }
        saveContext()
    }

    private func closeCurrentEvent() {
        if let current = currentEvent {
            let duration = Date().timeIntervalSince(current.timestamp)
            current.duration = max(1.0, duration)
            saveContext()
            currentEvent = nil
        }
    }
    
    private var shouldTrackWindowTitles: Bool {
        UserDefaults.standard.bool(forKey: "isPro") && UserDefaults.standard.bool(forKey: "ai_share_window_titles")
    }

    private func pollActiveWindow() {
        guard let frontmostApp = workspace.frontmostApplication else { return }
        let appName = frontmostApp.localizedName ?? "Unknown App"
        
        if appName == "loginwindow" {
            closeCurrentEvent()
            return
        }
        
        var windowTitle = ""
        var normalizedTitle = ""
        if hasAccessibilityPermission && shouldTrackWindowTitles {
            windowTitle = getActiveWindowTitle(for: frontmostApp)
            normalizedTitle = normalizeWindowTitle(windowTitle)
        }
        
        if let current = currentEvent {
            if current.appName == appName {
                let currentNormalized = normalizeWindowTitle(current.windowTitle)
                if currentNormalized == normalizedTitle {
                    if current.windowTitle != windowTitle {
                        current.windowTitle = windowTitle
                        saveContext()
                    }
                    emptyTitleBufferStart = nil
                    return
                }
                if normalizedTitle.isEmpty {
                    if let start = emptyTitleBufferStart {
                        if Date().timeIntervalSince(start) < 3.0 { return }
                    } else {
                        emptyTitleBufferStart = Date()
                        return
                    }
                }
            }
        }
        
        emptyTitleBufferStart = nil
        closeCurrentEvent()
        
        // Fast-path: check if we can resume the very last event in DB
        var fetchDescriptor = FetchDescriptor<ActivityEvent>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        fetchDescriptor.fetchLimit = 1
        if let lastEvent = try? modelContext.fetch(fetchDescriptor).first {
            let lastNormalized = normalizeWindowTitle(lastEvent.windowTitle)
            if lastEvent.appName == appName && lastNormalized == normalizedTitle {
                let endTime = lastEvent.timestamp.addingTimeInterval(lastEvent.duration)
                let gap = Date().timeIntervalSince(endTime)
                if gap < 15.0 {
                    lastEvent.duration = 0 // reopen
                    lastEvent.windowTitle = windowTitle
                    applyProductivityRule(to: lastEvent)
                    currentEvent = lastEvent
                    saveContext()
                    return
                }
            }
        }
        
        let newEvent = ActivityEvent(timestamp: Date(), duration: 0, appName: appName, bundleId: frontmostApp.bundleIdentifier, windowTitle: windowTitle)
        newEvent.category = categorize(appName: appName, windowTitle: windowTitle)
        applyProductivityRule(to: newEvent)
        modelContext.insert(newEvent)
        currentEvent = newEvent
        saveContext()
    }
    
    private func applyProductivityRule(to event: ActivityEvent) {
        let appName = event.appName.lowercased()
        let windowTitle = event.windowTitle.lowercased()
        
        for rule in cachedProductivityRules {
            if rule.appName.lowercased() == appName {
                let ruleTitle = rule.windowTitle.lowercased()
                if ruleTitle == windowTitle || (windowTitle.isEmpty && (ruleTitle.isEmpty || ruleTitle == "none")) {
                    event.isProductive = rule.isProductive
                    event.productivityReason = rule.reason
                    return
                }
            }
        }
    }
    
    private let localAppCategorization: [String: String] = [
        "Xcode": "Software Development", "Code": "Software Development", "Visual Studio Code": "Software Development", "Cursor": "Software Development", "Terminal": "Software Development", "iTerm2": "Software Development", "iTerm": "Software Development", "Warp": "Software Development", "Android Studio": "Software Development", "IntelliJ IDEA": "Software Development", "WebStorm": "Software Development", "PyCharm": "Software Development", "Postman": "Software Development", "Docker": "Software Development", "GitHub Desktop": "Software Development", "Sublime Text": "Software Development", "Simulator": "Software Development",
        "Slack": "Communication & Chat", "Discord": "Communication & Chat", "Telegram": "Communication & Chat", "Messages": "Communication & Chat", "WhatsApp": "Communication & Chat", "Microsoft Teams": "Communication & Chat", "Zoom": "Communication & Chat", "Mail": "Communication & Chat", "Spark": "Communication & Chat", "Viber": "Communication & Chat", "Skype": "Communication & Chat",
        "Google Chrome": "Web Browsing & Research", "Safari": "Web Browsing & Research", "Firefox": "Web Browsing & Research", "Arc": "Web Browsing & Research", "Brave Browser": "Web Browsing & Research", "Microsoft Edge": "Web Browsing & Research", "Opera": "Web Browsing & Research", "Yandex": "Web Browsing & Research",
        "Spotify": "Entertainment & Media", "Music": "Entertainment & Media", "Yandex Music": "Entertainment & Media", "VLC": "Entertainment & Media", "IINA": "Entertainment & Media", "QuickTime Player": "Entertainment & Media", "Podcasts": "Entertainment & Media", "TV": "Entertainment & Media", "Steam": "Entertainment & Media", "Epic Games Launcher": "Entertainment & Media", "Books": "Entertainment & Media",
        "Notes": "Productivity & Office", "Notion": "Productivity & Office", "Obsidian": "Productivity & Office", "Microsoft Word": "Productivity & Office", "Microsoft Excel": "Productivity & Office", "Microsoft PowerPoint": "Productivity & Office", "Pages": "Productivity & Office", "Numbers": "Productivity & Office", "Keynote": "Productivity & Office", "Calendar": "Productivity & Office", "Reminders": "Productivity & Office", "TickTick": "Productivity & Office", "Things": "Productivity & Office", "Todoist": "Productivity & Office", "Linear": "Productivity & Office", "Trello": "Productivity & Office", "Craft": "Productivity & Office",
        "Figma": "Design & Creativity", "Adobe Photoshop": "Design & Creativity", "Adobe Illustrator": "Design & Creativity", "Adobe Premiere Pro": "Design & Creativity", "Final Cut Pro": "Design & Creativity", "Sketch": "Design & Creativity", "Blender": "Design & Creativity", "Pixelmator Pro": "Design & Creativity", "Lightroom": "Design & Creativity", "DaVinci Resolve": "Design & Creativity", "Affinity Designer": "Design & Creativity", "Affinity Photo": "Design & Creativity",
        "Finder": "System & Utilities", "System Settings": "System & Utilities", "System Preferences": "System & Utilities", "Activity Monitor": "System & Utilities", "1Password": "System & Utilities", "Alfred 5": "System & Utilities", "Alfred": "System & Utilities", "Raycast": "System & Utilities", "FocusGuard": "System & Utilities", "Preview": "System & Utilities", "App Store": "System & Utilities", "Calculator": "System & Utilities", "Dictionary": "System & Utilities", "CleanMyMac X": "System & Utilities", "Istats Menus": "System & Utilities"
    ]
    
    private func getCategoryConfig(name: String) -> String {
        switch name {
        case "Software Development": return "#3498db"
        case "Communication & Chat": return "#e74c3c"
        case "Web Browsing & Research": return "#2ecc71"
        case "Entertainment & Media": return "#9b59b6"
        case "Productivity & Office": return "#f1c40f"
        case "Design & Creativity": return "#e67e22"
        case "System & Utilities": return "#95a5a6"
        default: return "#bdc3c7"
        }
    }

    private func categorize(appName: String, windowTitle: String) -> Category? {
        for category in cachedCategories {
            guard let rules = category.rules else { continue }
            for rule in rules { if rule.matches(appName) { return category } }
        }
        
        if let defaultCategoryName = localAppCategorization[appName] {
            var targetCategory = cachedCategories.first(where: { $0.name.lowercased() == defaultCategoryName.lowercased() })
            if targetCategory == nil {
                let colorHex = getCategoryConfig(name: defaultCategoryName)
                let newCat = Category(name: defaultCategoryName, colorHex: colorHex)
                modelContext.insert(newCat)
                targetCategory = newCat
                refreshCaches() // Update cache immediately
            }
            if let cat = targetCategory {
                let rule = CategoryRule(pattern: appName, matchType: .contains)
                rule.category = cat
                if cat.rules == nil { cat.rules = [] }
                cat.rules?.append(rule)
                modelContext.insert(rule)
                saveContext()
                return cat
            }
        }
        return nil
    }
    
    // Compiled once at class load time — avoids recompiling on every 0.5s poll.
    private static let normalizationRegexes: [NSRegularExpression] = {
        let patterns = ["^\\(\\d+\\)\\s*", "\\s*-\\s*\\(\\d+\\)$", "\\s*\\(\\d+\\)$", "^\\[\\d+\\]\\s*", "\\s*\\[\\d+\\]$"]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private func normalizeWindowTitle(_ title: String) -> String {
        var normalized = title
        for regex in Self.normalizationRegexes {
            let range = NSRange(location: 0, length: normalized.utf16.count)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func getActiveWindowTitle(for app: NSRunningApplication) -> String {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        var frontWindow: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &frontWindow)
        guard err == .success, let fw = frontWindow, CFGetTypeID(fw) == AXUIElementGetTypeID() else { return "" }
        let windowElement = fw as! AXUIElement
        var title: CFTypeRef?
        let errTitle = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title)
        if errTitle == .success, let titleStr = title as? String { return titleStr }
        return ""
    }
    
    deinit {
        trackingTimer?.invalidate()
        if let observer = rulesObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
