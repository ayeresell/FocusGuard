//
//  FocusGuardApp.swift
//  FocusGuard
//

import SwiftUI
import SwiftData
import Observation

@main
struct FocusGuardApp: App {
    let sharedModelContainer: ModelContainer
    @State private var trackingService: TrackingService
    @State private var aiService = AIService()

    init() {
        let schema = Schema([ActivityEvent.self, Category.self, CategoryRule.self, ProductivityRule.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.sharedModelContainer = container
            _trackingService = State(wrappedValue: TrackingService(modelContext: container.mainContext))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup(id: "dashboard") {
            ContentView()
                .environment(trackingService)
                .environment(aiService)
        }
        .modelContainer(sharedModelContainer)
        
        MenuBarExtra("FocusGuard", systemImage: "timer") {
            MenuBarView()
                .environment(trackingService)
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
// TODO: global keyboard shortcut for menu bar toggle
