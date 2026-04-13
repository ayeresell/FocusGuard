//
//  MenuBarView.swift
//  FocusGuard
//

import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Query private var recentEvents: [ActivityEvent]
    @Environment(\.openWindow) private var openWindow
    @Environment(TrackingService.self) private var trackingService
    
    init() {
        var descriptor = FetchDescriptor<ActivityEvent>(
            predicate: #Predicate { $0.appName != "loginwindow" && $0.appName != "FocusGuard" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        _recentEvents = Query(descriptor)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit FocusGuard")
            }
            .padding(.bottom, 4)
            
            if !trackingService.hasAccessibilityPermission {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Window Titles Disabled")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("Grant Permission") {
                        trackingService.requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.bottom, 4)
            }
            
            if recentEvents.isEmpty {
                Text("No activity yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(recentEvents) { event in
                    HStack(spacing: 8) {
                        AppIconView(appName: event.appName, bundleId: event.bundleId, size: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.appName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if !event.windowTitle.isEmpty {
                                Text(event.windowTitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        Spacer()
                        if event.duration == 0 {
                            Text(event.timestamp, style: .timer)
                                .foregroundColor(.blue)
                                .font(.callout.monospacedDigit())
                        } else {
                            Text(formatDuration(event.duration))
                                .foregroundColor(.secondary)
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            Button(action: {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }) {
                Text("Open Dashboard")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("d", modifiers: .command)
        }
        .padding()
        .frame(width: 250)
    }
    
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        return Self.formatter.string(from: duration) ?? "\(Int(duration))s"
    }
}