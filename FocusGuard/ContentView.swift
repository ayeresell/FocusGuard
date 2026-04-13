//
//  ContentView.swift
//  FocusGuard
//

import SwiftUI
import SwiftData
import Charts
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ActivityEvent> { $0.appName != "loginwindow" && $0.appName != "FocusGuard" }, sort: \ActivityEvent.timestamp, order: .reverse) private var events: [ActivityEvent]
    
    @State private var visibleItems: Set<PersistentIdentifier> = []
    
    @State private var selectedEvent: ActivityEvent?
    @State private var activeTab: AppTab = .dashboard
    @Namespace private var activeTabNamespace
    
    @Environment(TrackingService.self) private var trackingService
    
    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
    }
    
    @State private var selectedTimeRange: TimeRange = .today
    
    enum AppTab: String, CaseIterable {
        case dashboard = "Dashboard"
        case analytics = "Analytics"
        case categories = "Categories"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .dashboard: return "chart.xyaxis.line"
            case .analytics: return "chart.pie.fill"
            case .categories: return "square.grid.3x3.fill"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    private var filteredTimeEvents: [ActivityEvent] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        
        switch selectedTimeRange {
        case .today:
            return events.filter { $0.timestamp >= startOfToday }
        case .week:
            let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
            return events.filter { $0.timestamp >= startOfWeek }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    // Sticky Header
                    HStack {
                        Text("Recent Activity")
                            .font(.system(.caption, design: .rounded))
                            .bold()
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        Button(action: {
                            if let firstId = events.first?.persistentModelID {
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    proxy.scrollTo(firstId, anchor: .top)
                                }
                            }
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Scroll to top")
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                    .zIndex(1)
                    
                    // Scrollable List without internal header
                    List(selection: $selectedEvent) {
                        ForEach(events.prefix(50)) { event in
                            ActivityRow(event: event)
                                .tag(event)
                                .id(event.persistentModelID)
                                .onAppear {
                                    visibleItems.insert(event.persistentModelID)
                                }
                                .onDisappear {
                                    visibleItems.remove(event.persistentModelID)
                                }
                        }
                        .onDelete(perform: deleteEvents)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .animation(.default, value: events.first?.persistentModelID)
                    .onChange(of: events.first?.persistentModelID) { oldValue, newValue in
                        guard let newId = newValue, let oldId = oldValue, oldId != newId else { return }
                        
                        // Если предыдущий первый элемент был видим (то есть мы находились на самом верху),
                        // то плавно скроллим к новому, оставаясь "на самом верху".
                        // Если мы пролистнули вниз, список не дернется.
                        if visibleItems.contains(oldId) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                proxy.scrollTo(newId, anchor: .top)
                            }
                        }
                    }
                }
                
                // Footer
                HStack {
                    Button(action: deleteAll) {
                        Label("Clear All", systemImage: "trash.slash.fill")
                    }
                    .buttonStyle(GlassyButtonStyle(color: .red))
                    Spacer()
                    Text("\(events.count) Total")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(.ultraThinMaterial)
                .overlay(VStack { Divider().opacity(0.2); Spacer() })
            }
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    if selectedEvent != nil {
                        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedEvent = nil } }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left.circle.fill")
                                Text("Back")
                            }
                        }
                        .buttonStyle(GlassyButtonStyle())
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    } else if activeTab == .dashboard || activeTab == .analytics {
                        Picker("", selection: $selectedTimeRange) {
                            ForEach(TimeRange.allCases, id: \.self) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .transition(.opacity)
                    }
                    
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(AppTab.allCases, id: \.self) { tab in
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon).imageScale(.small)
                                Text(tab.rawValue)
                            }
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundColor(activeTab == tab ? .primary : .secondary)
                            .background {
                                if activeTab == tab {
                                    Capsule().fill(.white.opacity(0.18))
                                        .matchedGeometryEffect(id: "activeTab", in: activeTabNamespace)
                                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1.5)
                                }
                            }
                            .contentShape(Capsule())
                            .onHover { hovering in
                                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    activeTab = tab
                                    selectedEvent = nil
                                }
                            }
                        }
                    }
                    .padding(4).background(.ultraThinMaterial).clipShape(Capsule())
                    .overlay(Capsule().stroke(.primary.opacity(0.15), lineWidth: 0.5))
                    .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
                    Spacer()
                }
                .padding(.horizontal, 20).frame(height: 52).background(.ultraThinMaterial)
                .overlay(VStack { Spacer(); Divider().opacity(0.2) }).zIndex(1)
                
                ZStack {
                    if let selected = selectedEvent {
                        EventDetailView(event: selected)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    } else {
                        Group {
                            switch activeTab {
                            case .dashboard:
                                DashboardOverviewTab(events: filteredTimeEvents)
                            case .analytics:
                                ProAnalyticsTab(events: filteredTimeEvents, timeRange: selectedTimeRange)
                            case .categories:
                                CategoriesManagementTab()
                            case .settings:
                                AISettingsView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        }
        .frame(minWidth: 1100, minHeight: 750)
    }
    
    private func deleteEvents(offsets: IndexSet) {
        withAnimation { 
            let visibleEvents = Array(events.prefix(50))
            for index in offsets { 
                modelContext.delete(visibleEvents[index]) 
            } 
        }
    }
    
    private func deleteAll() {
        withAnimation {
            for event in events { modelContext.delete(event) }
            selectedEvent = nil
        }
    }
}

enum DashboardWidget: String, CaseIterable, Identifiable, Codable {
    case totalTracked = "Total Tracked"
    case primaryFocus = "Primary Focus"
    case appSwitches = "App Switches"
    case categories = "Time by Category"
    case aiInsights = "AI Insights"
    case topApps = "Top Applications"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .totalTracked: return "timer"
        case .primaryFocus: return "target"
        case .appSwitches: return "arrow.left.arrow.right"
        case .categories: return "chart.pie.fill"
        case .aiInsights: return "brain.fill"
        case .topApps: return "macwindow.on.rectangle"
        }
    }
    
    enum SizeClass: String, Codable { case small, medium, large }

    var sizeClass: SizeClass {
        switch self {
        case .totalTracked, .primaryFocus, .appSwitches: return .small
        case .categories, .aiInsights: return .medium
        case .topApps: return .large
        }
    }

    var defaultColumnWidth: ColumnWidth {
        switch self {
        case .totalTracked, .primaryFocus, .appSwitches: return .oneThird
        case .categories, .aiInsights: return .half
        case .topApps: return .full
        }
    }
}

enum ColumnWidth: String, Codable, CaseIterable, Equatable {
    case oneThird  = "⅓"
    case half      = "½"
    case twoThirds = "⅔"
    case full      = "↔"

    var fraction: CGFloat {
        switch self {
        case .oneThird:  return 1.0 / 3.0
        case .half:      return 1.0 / 2.0
        case .twoThirds: return 2.0 / 3.0
        case .full:      return 1.0
        }
    }
}

struct WidgetState: Identifiable, Codable, Equatable {
    var type: DashboardWidget
    var isVisible: Bool
    var customSize: DashboardWidget.SizeClass? = nil
    var columnWidth: ColumnWidth? = nil      // nil = use type's default
    var columnGroupId: String? = nil         // widgets with same ID stack in one column

    var id: String { type.rawValue }

    var effectiveSize: DashboardWidget.SizeClass {
        customSize ?? type.sizeClass
    }

    var effectiveColumnWidth: ColumnWidth {
        columnWidth ?? type.defaultColumnWidth
    }
}

struct DashboardOverviewTab: View {
    var events: [ActivityEvent]
    @Environment(AIService.self) private var aiService

    @AppStorage("isPro") private var isPro: Bool = false
    @AppStorage("dashboard_layout_data") private var layoutData: Data = Data()

    // A column group: one or more widgets stacked vertically, sharing a column fraction.
    struct ColumnGroup: Identifiable {
        let id: String
        let fraction: CGFloat
        var widgets: [WidgetState]
    }

    @State private var layout: [WidgetState] = []
    @State private var isEditingLayout = false
    @State private var dropTargetId: String? = nil
    @State private var cachedRows: [[ColumnGroup]] = []
    @State private var hoveredWidthKey: String? = nil  // "\(widgetId)-\(columnWidth)"

    struct CategoryAgg: Identifiable {
        var id: String { name }
        let name: String; let color: Color; let duration: TimeInterval
    }

    private var metrics: (totalTime: TimeInterval, prodPercent: Double, categoryData: [CategoryAgg], topApps: [(name: String, categoryName: String, categoryColor: Color, duration: TimeInterval)], contextSwitches: Int, primaryFocus: (name: String, percent: Double)?) {
        var total: TimeInterval = 0
        var prodTime: TimeInterval = 0
        var dict: [String: (Color, TimeInterval)] = [:]
        var appDict: [String: (TimeInterval, String, Color)] = [:]
        var switches = 0
        
        let now = Date()
        var previousAppName: String? = nil
        
        // events is already sorted in reverse order (newest first).
        // By iterating reversed(), we process from oldest to newest efficiently without O(N log N) sorting.
        for event in events.reversed() {
            let dur = (event.duration == 0 ? max(0, now.timeIntervalSince(event.timestamp)) : event.duration)
            total += dur
            
            if event.isProductive == true {
                prodTime += dur
            }
            
            let name = event.category?.name ?? "Uncategorized"
            let color = event.category?.color ?? .gray.opacity(0.5)
            let current = dict[name] ?? (color, 0)
            dict[name] = (color, current.1 + dur)
            
            let appData = appDict[event.appName] ?? (0, name, color)
            appDict[event.appName] = (appData.0 + dur, name, color)
            
            if let prev = previousAppName, prev != event.appName {
                switches += 1
            }
            previousAppName = event.appName
        }
        
        let totalTime = total
        let prodPercent = total > 0 ? (prodTime / total) * 100 : 0
        let categoryData = dict.map { CategoryAgg(name: $0.key, color: $0.value.0, duration: $0.value.1) }.sorted { $0.duration > $1.duration }
        let topApps = appDict.map { (name: $0.key, categoryName: $0.value.1, categoryColor: $0.value.2, duration: $0.value.0) }.sorted { $0.duration > $1.duration }
        
        var primaryFocus: (name: String, percent: Double)? = nil
        if let topCategory = categoryData.first, total > 0 {
            primaryFocus = (topCategory.name, (topCategory.duration / total) * 100)
        }
        
        return (totalTime, prodPercent, categoryData, topApps, switches, primaryFocus)
    }

    private var runningEventInfo: (base: TimeInterval, start: Date)? {
        guard let running = events.first(where: { $0.duration == 0 }) else { return nil }
        let base = events.filter { $0.duration > 0 }.reduce(0.0) { $0 + $1.duration }
        return (base, running.timestamp)
    }

    var body: some View {
        let currentMetrics = metrics
        let visibleWidgets = layout.filter { $0.isVisible }

        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        if isEditingLayout {
                            Text("Editing Layout")
                                .font(.system(.headline, design: .rounded))
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    layout = DashboardWidget.allCases.map { WidgetState(type: $0, isVisible: true) }
                                    saveLayout()
                                }
                            }) {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(GlassyButtonStyle(color: .orange))
                        } else {
                            Spacer()
                        }

                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if isEditingLayout {
                                    saveLayout()
                                }
                                isEditingLayout.toggle()
                            }
                        }) {
                            Label(isEditingLayout ? "Done" : "Edit Layout", systemImage: isEditingLayout ? "checkmark.circle.fill" : "slider.horizontal.3")
                        }
                        .buttonStyle(GlassyButtonStyle(color: isEditingLayout ? .green : .primary, isProminent: isEditingLayout))
                    }
                    .padding(.bottom, isEditingLayout ? 5 : -15)
                    
                    if isEditingLayout {
                        let hiddenWidgets = layout.filter { !$0.isVisible }
                        if !hiddenWidgets.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(hiddenWidgets) { widgetState in
                                        Button(action: {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                if let idx = layout.firstIndex(where: { $0.id == widgetState.id }) {
                                                    layout[idx].isVisible = true
                                                }
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "plus.circle.fill").foregroundColor(.green)
                                                Text(widgetState.type.rawValue)
                                            }
                                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(.thinMaterial)
                                            .cornerRadius(12)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.1), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .padding(.bottom, -10)
                        }
                    }
                    
                    if visibleWidgets.isEmpty && !isEditingLayout {
                        VStack(spacing: 20) {
                            Image(systemName: "eye.slash.fill").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                            Text("All widgets hidden").font(.headline)
                            Button("Edit Layout") { 
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    isEditingLayout = true 
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        let gap: CGFloat = 16
                        let available = geo.size.width - 60   // 30pt padding each side

                        VStack(alignment: .leading, spacing: gap) {
                            ForEach(cachedRows.indices, id: \.self) { ri in
                                let row = cachedRows[ri]
                                // Compute the tallest column group height so all groups in the row match
                                let rowHeight = row.map { colGroupHeight($0, gap: gap) }.max() ?? 140
                                HStack(alignment: .top, spacing: gap) {
                                    ForEach(row) { colGroup in
                                        let ww = max(80, (available - gap * CGFloat(row.count - 1)) * colGroup.fraction)
                                        if colGroup.widgets.count == 1 {
                                            let ws = colGroup.widgets[0]
                                            widgetCell(ws, ww: ww, rh: rowHeight, metrics: currentMetrics, gap: gap)
                                        } else {
                                            // Stacked column: divide row height evenly among widgets
                                            let perWidget = (rowHeight - gap * CGFloat(colGroup.widgets.count - 1)) / CGFloat(colGroup.widgets.count)
                                            VStack(spacing: gap) {
                                                ForEach(colGroup.widgets) { ws in
                                                    widgetCell(ws, ww: ww, rh: max(80, perWidget), metrics: currentMetrics, gap: gap)
                                                }
                                            }
                                            .frame(width: ww)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear { loadLayout() }
        .onChange(of: layout) { _, _ in updateCachedRows(animated: true) }
    }

    private func updateCachedRows(animated: Bool) {
        let rows = groupIntoRows(layout.filter { $0.isVisible })
        if animated {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { cachedRows = rows }
        } else {
            cachedRows = rows
        }
    }

    // Preferred height for a single widget.
    private func heightForWidget(_ ws: WidgetState) -> CGFloat {
        switch ws.type {
        case .totalTracked, .primaryFocus, .appSwitches: return 140
        case .categories:   return 320
        case .aiInsights:   return 280
        case .topApps:      return 260
        }
    }

    // Total height of a column group (stacked widgets include inter-widget gaps).
    private func colGroupHeight(_ group: ColumnGroup, gap: CGFloat) -> CGFloat {
        if group.widgets.count == 1 {
            return heightForWidget(group.widgets[0])
        }
        let totalWidgetHeight = group.widgets.reduce(CGFloat(0)) { $0 + heightForWidget($1) }
        return totalWidgetHeight + gap * CGFloat(group.widgets.count - 1)
    }

    // A single draggable+droppable widget cell.
    @ViewBuilder
    private func widgetCell(_ ws: WidgetState, ww: CGFloat, rh: CGFloat, metrics: (totalTime: TimeInterval, prodPercent: Double, categoryData: [CategoryAgg], topApps: [(name: String, categoryName: String, categoryColor: Color, duration: TimeInterval)], contextSwitches: Int, primaryFocus: (name: String, percent: Double)?), gap: CGFloat) -> some View {
        let isTarget = dropTargetId == ws.id
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                renderWidget(ws.type, metrics: metrics, availableWidth: ww)
                    .allowsHitTesting(!isEditingLayout)
                    .overlay {
                        if isEditingLayout {
                            // Transparent overlay that captures drag gestures
                            // instead of letting widget buttons consume them
                            Color.clear
                                .contentShape(Rectangle())
                        }
                    }
                    .scaleEffect(isEditingLayout ? (isTarget ? 1.02 : 0.97) : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isTarget ? Color.accentColor.opacity(0.6) : (isEditingLayout ? Color.primary.opacity(0.15) : .clear), lineWidth: isTarget ? 2.5 : 1)
                            .overlay(
                                isEditingLayout && !isTarget
                                    ? RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                        .foregroundColor(.primary.opacity(0.12))
                                    : nil
                            )
                    )
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isTarget)

                if isEditingLayout {
                    // Remove button — top-left
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if let idx = layout.firstIndex(where: { $0.id == ws.id }) {
                                layout[idx].isVisible = false
                                layout[idx].columnGroupId = nil
                            }
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.red)
                            .background(Circle().fill(.white).padding(2))
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -8, y: -8)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)

                    // Drag handle — top-right
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 2) {
                                ForEach(0..<2, id: \.self) { _ in
                                    Circle().fill(.secondary.opacity(0.5)).frame(width: 4, height: 4)
                                }
                            }
                        }
                    }
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: -10, y: 10)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .frame(width: ww, height: rh)
            .draggable(ws.id) {
                // Lightweight preview — avoids re-rendering full widget during drag (main lag source)
                HStack(spacing: 8) {
                    Image(systemName: ws.type.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(ws.type.rawValue)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            .dropDestination(for: String.self) { items, _ in
                guard isEditingLayout,
                      let fromId = items.first, fromId != ws.id,
                      let from = layout.firstIndex(where: { $0.id == fromId }),
                      let to   = layout.firstIndex(where: { $0.id == ws.id })
                else { return false }
                layout.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                dropTargetId = nil
                saveLayout()
                return true
            } isTargeted: { targeted in
                if isEditingLayout {
                    dropTargetId = targeted ? ws.id : (dropTargetId == ws.id ? nil : dropTargetId)
                }
            }

            if isEditingLayout {
                widthPicker(for: ws, ww: ww)
                    .frame(width: ww)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.top, 6)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isEditingLayout)
    }

    private func loadLayout() {
        if let decoded = try? JSONDecoder().decode([WidgetState].self, from: layoutData), !decoded.isEmpty {
            var newLayout = decoded
            for type in DashboardWidget.allCases {
                if !newLayout.contains(where: { $0.type == type }) {
                    newLayout.append(WidgetState(type: type, isVisible: true))
                }
            }
            self.layout = newLayout
        } else {
            self.layout = DashboardWidget.allCases.map { WidgetState(type: $0, isVisible: true) }
        }
        updateCachedRows(animated: false)
    }
    
    private func saveLayout() {
        if let encoded = try? JSONEncoder().encode(layout) {
            layoutData = encoded
        }
    }

    // Groups visible widgets into rows, consolidating same-columnGroupId widgets into stacked ColumnGroups.
    private func groupIntoRows(_ widgets: [WidgetState]) -> [[ColumnGroup]] {
        // Step 1: consolidate consecutive same-groupId widgets into column groups
        var groups: [ColumnGroup] = []
        var i = 0
        while i < widgets.count {
            let w = widgets[i]
            if let gid = w.columnGroupId {
                var grpWidgets = [w]
                var j = i + 1
                while j < widgets.count, widgets[j].columnGroupId == gid {
                    grpWidgets.append(widgets[j])
                    j += 1
                }
                groups.append(ColumnGroup(id: gid, fraction: w.effectiveColumnWidth.fraction, widgets: grpWidgets))
                i = j
            } else {
                groups.append(ColumnGroup(id: w.id, fraction: w.effectiveColumnWidth.fraction, widgets: [w]))
                i += 1
            }
        }

        // Step 2: pack column groups into rows (fractions must sum ≤ 1.0)
        var rows: [[ColumnGroup]] = []
        var currentRow: [ColumnGroup] = []
        var usedFraction: CGFloat = 0

        for g in groups {
            if !currentRow.isEmpty && usedFraction + g.fraction > 1.001 {
                rows.append(currentRow)
                currentRow = [g]
                usedFraction = g.fraction
            } else {
                currentRow.append(g)
                usedFraction += g.fraction
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }
        return rows
    }

    // Apple-style segmented width picker + stack button.
    @ViewBuilder
    private func widthPicker(for ws: WidgetState, ww: CGFloat) -> some View {
        VStack(spacing: 5) {
            // Width selector — segmented style with instant hover feedback
            HStack(spacing: 1) {
                ForEach(ColumnWidth.allCases, id: \.self) { w in
                    let selected = ws.effectiveColumnWidth == w
                    let hoverKey = "\(ws.id)-\(w.rawValue)"
                    let isHovered = hoveredWidthKey == hoverKey
                    Button {
                        if let idx = layout.firstIndex(where: { $0.id == ws.id }) {
                            layout[idx].columnWidth = w
                        }
                        saveLayout()
                    } label: {
                        Text(w.rawValue)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selected
                                        ? Color.accentColor
                                        : (isHovered ? Color.accentColor.opacity(0.12) : Color.clear))
                            )
                            .foregroundColor(selected ? .white : (isHovered ? .accentColor : .secondary))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredWidthKey = hovering ? hoverKey : nil
                    }
                }
            }
            .padding(3)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.primary.opacity(0.08), lineWidth: 0.5))

            // Stack button — only shown for ⅓ widgets
            if ws.effectiveColumnWidth == .oneThird {
                stackButton(for: ws)
            }
        }
        .padding(.horizontal, 6)
    }

    // Stacks/unstacks this widget with the next visible ⅓ widget.
    @ViewBuilder
    private func stackButton(for ws: WidgetState) -> some View {
        let isStacked = ws.columnGroupId != nil
        let hoverKey = "\(ws.id)-stack"
        let isHovered = hoveredWidthKey == hoverKey

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                toggleStack(for: ws)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isStacked ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle")
                    .font(.system(size: 10, weight: .medium))
                Text(isStacked ? "Unstack" : "Stack")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isStacked
                        ? Color.orange.opacity(isHovered ? 0.22 : 0.15)
                        : Color.accentColor.opacity(isHovered ? 0.16 : 0.1))
            )
            .foregroundColor(isStacked ? .orange : .accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredWidthKey = hovering ? hoverKey : nil }
    }

    private func toggleStack(for ws: WidgetState) {
        guard let idx = layout.firstIndex(where: { $0.id == ws.id }) else { return }
        if let gid = ws.columnGroupId {
            // Remove from group — if only one widget remains, dissolve the group
            layout[idx].columnGroupId = nil
            let remaining = layout.filter { $0.columnGroupId == gid }
            if remaining.count == 1, let other = remaining.first,
               let otherIdx = layout.firstIndex(where: { $0.id == other.id }) {
                layout[otherIdx].columnGroupId = nil
            }
        } else {
            // Stack with the next visible ⅓ widget
            let visibleBefore = layout.filter { $0.isVisible }
            guard let posInVisible = visibleBefore.firstIndex(where: { $0.id == ws.id }) else { return }
            let candidates = visibleBefore[(posInVisible + 1)...]
            if let target = candidates.first(where: { $0.effectiveColumnWidth == .oneThird }),
               let targetIdx = layout.firstIndex(where: { $0.id == target.id }) {
                // If target already belongs to a group, join that group; else create a new one
                let gid = target.columnGroupId ?? UUID().uuidString
                layout[idx].columnGroupId = gid
                layout[targetIdx].columnGroupId = gid
            }
        }
        saveLayout()
    }

    @ViewBuilder
    private func renderWidget(_ type: DashboardWidget, metrics: (totalTime: TimeInterval, prodPercent: Double, categoryData: [CategoryAgg], topApps: [(name: String, categoryName: String, categoryColor: Color, duration: TimeInterval)], contextSwitches: Int, primaryFocus: (name: String, percent: Double)?), availableWidth: CGFloat) -> some View {
        switch type {
        case .totalTracked:
            SummaryCard(title: "Total Tracked", value: metrics.totalTime.formatHMS(), icon: "timer", color: .blue, liveTimer: runningEventInfo)
        case .primaryFocus:
            if let focus = metrics.primaryFocus {
                SummaryCard(title: "Primary Focus", value: String(format: "%.0f%%", focus.percent), icon: "target", color: .purple, subValue: focus.name)
            } else {
                SummaryCard(title: "Primary Focus", value: "0%", icon: "target", color: .purple, subValue: "No data")
            }
        case .appSwitches:
            SummaryCard(title: "App Switches", value: "\(metrics.contextSwitches)", icon: "arrow.left.arrow.right", color: .orange, subValue: "times")
        case .categories:
            DashboardInteractiveChart(data: metrics.categoryData, availableWidth: availableWidth, liveTimer: runningEventInfo)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .aiInsights:
            aiInsightsWidget()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .topApps:
            topAppsWidget(topApps: metrics.topApps, availableWidth: availableWidth)
        }
    }
    
    @ViewBuilder
    private func aiInsightsWidget() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Insights", systemImage: "brain.fill").font(.system(.headline, design: .rounded)).foregroundColor(.purple)
                if !isPro { ProBadge() }
                Spacer()
                if isPro && !aiService.apiKey.isEmpty {
                    Button(action: { Task { await aiService.generateDailyInsights(events: events) } }) {
                        if aiService.isProcessingInsights { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise.heart") }
                    }.buttonStyle(GlassyButtonStyle(color: .purple))
                }
            }
            if !isPro {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Unlock daily AI-generated summaries of your focus and distractions.").font(.subheadline).foregroundColor(.secondary)
                    Button(action: { withAnimation { isPro = true } }) {
                        Text("Upgrade to Pro")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            } else if aiService.apiKey.isEmpty { Text("Connect API for insights.").font(.caption).foregroundColor(.secondary) }
            else if aiService.lastSummary.isEmpty { Text("No analysis yet.").font(.caption).foregroundColor(.secondary) }
            else { Text(aiService.lastSummary).font(.system(.subheadline, design: .rounded)).lineSpacing(4) }
            Spacer(minLength: 0)
        }
        .dashboardWidgetStyle()
    }
    
    @ViewBuilder
    private func topAppsWidget(topApps: [(name: String, categoryName: String, categoryColor: Color, duration: TimeInterval)], availableWidth: CGFloat) -> some View {
        let apps = Array(topApps.prefix(5))

        VStack(alignment: .leading, spacing: 12) {
            Label("Top Applications", systemImage: "macwindow.on.rectangle")
                .font(.system(.headline, design: .rounded))
            VStack(spacing: 6) {
                ForEach(apps, id: \.name) { appRow($0) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .liquidGlass(cornerRadius: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func appRow(_ app: (name: String, categoryName: String, categoryColor: Color, duration: TimeInterval)) -> some View {
        HStack(spacing: 10) {
            AppIconView(appName: app.name, bundleId: nil, size: 22)
            HStack(spacing: 6) {
                Circle().fill(app.categoryColor).frame(width: 5, height: 5)
                Text(app.name)
                    .font(.system(.subheadline, design: .rounded))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(app.duration.formatHMS())
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.5))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.07), lineWidth: 1))
    }
}


struct DashboardInteractiveChart: View {
    let data: [DashboardOverviewTab.CategoryAgg]
    var availableWidth: CGFloat = 400
    var liveTimer: (base: TimeInterval, start: Date)? = nil
    @State private var hoveredCategory: String? = nil

    // At narrow widths legend is hidden to give chart more room.
    private var showLegend: Bool { availableWidth >= 260 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Time by Category", systemImage: "chart.pie.fill")
                .font(.system(.headline, design: .rounded))
            if data.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie").font(.system(size: 32)).foregroundColor(.secondary.opacity(0.3))
                    Text("No data yet").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                chartView(data: data)
                if showLegend { legendView(data: data) }
            }
        }
        .dashboardWidgetStyle()
    }

    private func handleHover(location: CGPoint, plotFrame: CGRect, data: [DashboardOverviewTab.CategoryAgg]) {
        let dx = location.x - plotFrame.midX
        let dy = location.y - plotFrame.midY
        let distance = sqrt(dx * dx + dy * dy)
        let outerRadius = min(plotFrame.width, plotFrame.height) / 2
        
        var foundCategory: String? = nil
        
        if distance >= outerRadius * 0.65 && distance <= outerRadius {
            var angle = atan2(dy, dx) + .pi / 2
            if angle < 0 { angle += 2 * .pi }
            
            let totalDuration = data.reduce(0) { $0 + $1.duration }
            if totalDuration > 0 {
                let hoveredValue = (angle / (2 * .pi)) * totalDuration
                var currentAccumulator: Double = 0
                for item in data {
                    currentAccumulator += item.duration
                    if hoveredValue <= currentAccumulator {
                        foundCategory = item.name
                        break
                    }
                }
            }
        }
        
        if hoveredCategory != foundCategory {
            hoveredCategory = foundCategory
        }
    }

    private func chartView(data: [DashboardOverviewTab.CategoryAgg]) -> some View {
        let totalDuration = data.reduce(0) { $0 + $1.duration }
        let minimumVisibleDuration = totalDuration * 0.01 // Guarantee at least 1% visual size
        
        // Create an adjusted dataset for rendering and hovering so they match exactly
        let visualData = data.map { item -> DashboardOverviewTab.CategoryAgg in
            DashboardOverviewTab.CategoryAgg(name: item.name, color: item.color, duration: max(item.duration, minimumVisibleDuration))
        }
        
        return ZStack {
            Chart(visualData) { item in
                SectorMark(angle: .value("Duration", item.duration), innerRadius: .ratio(0.65), angularInset: 2)
                .foregroundStyle(item.color)
                .cornerRadius(4)
                .opacity(hoveredCategory == nil || hoveredCategory == item.name ? 1.0 : 0.3)
            }.frame(maxHeight: .infinity)
            .animation(nil, value: hoveredCategory) // Disable chart's internal fading animation
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geometry[plotFrameAnchor]
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    handleHover(location: location, plotFrame: plotFrame, data: visualData) // Use visualData to match the chart
                                case .ended:
                                    if hoveredCategory != nil {
                                        hoveredCategory = nil
                                    }
                                }
                            }
                    }
                }
            }
            
            Group {
                if let hovered = hoveredCategory, let item = data.first(where: { $0.name == hovered }) {
                    let percent = totalDuration > 0 ? (item.duration / totalDuration) * 100 : 0
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f%%", percent))
                            .font(.system(.title2, design: .rounded)).bold()
                            .foregroundColor(item.color)
                        
                        Text(item.duration.formatHMS())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .id("hover-\(hovered)")
                } else {
                    VStack(spacing: 2) {
                        Text("Total")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if let live = liveTimer {
                            TimelineView(.periodic(from: Date(), by: 1.0)) { ctx in
                                let liveTotalDuration = live.base + max(0, ctx.date.timeIntervalSince(live.start))
                                Text(liveTotalDuration.formatHMS())
                                    .font(.system(.subheadline, design: .monospaced)).bold()
                                    .contentTransition(.numericText())
                            }
                        } else {
                            Text(totalDuration.formatHMS())
                                .font(.system(.subheadline, design: .monospaced)).bold()
                        }
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .id("total")
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hoveredCategory)
        }
    }

    private func legendView(data: [DashboardOverviewTab.CategoryAgg]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(data) { item in
                let isHovered = hoveredCategory == item.name
                
                HStack(spacing: 4) {
                    Circle().fill(item.color).frame(width: 6, height: 6)
                    Text(item.name)
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
            }
        }
    }
}

struct CategoriesManagementTab: View {
    @Environment(AIService.self) private var aiService
    @Environment(\.modelContext) private var modelContext
    @AppStorage("isPro") private var isPro: Bool = false
    @Query(filter: #Predicate<ActivityEvent> { $0.appName != "loginwindow" && $0.appName != "FocusGuard" }) private var events: [ActivityEvent]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Categories").font(.system(.title2, design: .rounded)).bold()
                        if !isPro { ProBadge() }
                    }
                    Text("Automatic grouping rules").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    if isPro {
                        Task { await aiService.categorizeUnknownApps(context: modelContext, events: events) }
                    } else {
                        withAnimation { isPro = true } // For testing purposes, act as upgrade
                    }
                }) {
                    if aiService.isProcessingCategories { ProgressView().controlSize(.small) }
                    else { 
                        HStack(spacing: 6) {
                            Image(systemName: isPro ? "sparkles.rectangle.stack.fill" : "lock.fill")
                            Text(isPro ? "Auto-Categorize" : "Unlock Pro")
                        }
                    }
                }.buttonStyle(GlassyButtonStyle(color: isPro ? .blue : .purple, isProminent: isPro))
            }
            .padding(20).background(.ultraThinMaterial.opacity(0.3)).overlay(VStack { Spacer(); Divider().opacity(0.2) })
            SettingsView()
        }
    }
}

struct ProAnalyticsTab: View {
    var events: [ActivityEvent]
    var timeRange: ContentView.TimeRange
    @Environment(AIService.self) private var aiService
    @Environment(\.modelContext) private var modelContext
    @Environment(TrackingService.self) private var trackingService
    @AppStorage("isPro") private var isPro: Bool = false
    
    private var analyzedEvents: [ActivityEvent] {
        events.filter { $0.isProductive != nil }
    }
    
    private var prodTime: TimeInterval {
        analyzedEvents.filter { $0.isProductive == true }.reduce(0) { $0 + ($1.duration == 0 ? max(0, Date().timeIntervalSince($1.timestamp)) : $1.duration) }
    }
    
    private var unprodTime: TimeInterval {
        analyzedEvents.filter { $0.isProductive == false }.reduce(0) { $0 + ($1.duration == 0 ? max(0, Date().timeIntervalSince($1.timestamp)) : $1.duration) }
    }
    
    private var prodScore: Double {
        let total = prodTime + unprodTime
        return total > 0 ? (prodTime / total) * 100 : 0
    }
    
    var body: some View {
        if !isPro {
            VStack {
                Spacer()
                PremiumLockView(title: "Pro Analytics", description: "Unlock AI-powered productivity trends, focus scores, and detailed distraction analysis.")
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if aiService.apiKey.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "key.viewfinder").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                Text("API Key Required").font(.headline)
                Text("Please configure your Gemini API Key in the Settings tab to enable AI analysis.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        else {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Productivity Trends").font(.system(.title2, design: .rounded)).bold()
                            Text("AI-powered analysis").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: { Task { await aiService.analyzeProductivity(context: modelContext, events: events) } }) {
                            if aiService.isProcessingProductivity { ProgressView().controlSize(.small) }
                            else { Label("Analyze Now", systemImage: "wand.and.stars") }
                        }.buttonStyle(GlassyButtonStyle(color: .blue, isProminent: true))
                    }
                    
                    if analyzedEvents.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "chart.bar.xaxis.ascending").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                            Text("No analyzed data yet.").font(.headline)
                            Text("Click 'Analyze Now' to let AI process your tracked activity and discover productivity trends.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .background(.thinMaterial).cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.15), lineWidth: 1))
                    } else {
                        HStack(spacing: 20) {
                            SummaryCard(title: "Focus Score", value: String(format: "%.0f%%", prodScore), icon: "target", color: prodScore >= 50 ? .green : .orange)
                            SummaryCard(title: "Focused Time", value: prodTime.formatHMS(), icon: "brain", color: .green)
                            SummaryCard(title: "Distracted Time", value: unprodTime.formatHMS(), icon: "bolt.slash.fill", color: .orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Label(timeRange == .today ? "Hourly Breakdown" : "Daily Breakdown", systemImage: timeRange == .today ? "clock.arrow.2.circlepath" : "calendar").font(.headline)
                            Chart(getProductivityTimeline()) { item in
                                BarMark(x: .value("Time", item.label), y: .value("Focus", item.prod / 60))
                                    .foregroundStyle(Color.green.gradient)
                                    .cornerRadius(2)
                                BarMark(x: .value("Time", item.label), y: .value("Distraction", -item.unprod / 60))
                                    .foregroundStyle(Color.orange.gradient)
                                    .cornerRadius(2)
                            }.frame(height: 220)
                            .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let mins = value.as(Double.self) { AxisValueLabel { Text("\(Int(abs(mins)))m") } } } }
                        }
                        .padding(20).background(.thinMaterial).cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.15), lineWidth: 1))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.15), lineWidth: 0.5))

                        HStack(alignment: .top, spacing: 25) {
                            VStack(alignment: .leading, spacing: 15) {
                                Label("Top Focus", systemImage: "brain.fill").font(.title3).bold().foregroundColor(.green)
                                ForEach(getTopProductive(), id: \.id) { item in
                                    HStack(spacing: 12) {
                                        AppIconView(appName: item.app, bundleId: nil, size: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.app).font(.subheadline).bold()
                                            Text(item.title).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Text(item.dur.formatHMS()).font(.system(.subheadline, design: .monospaced)).bold()
                                    }.padding(12).background(.ultraThinMaterial.opacity(0.4)).cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.15), lineWidth: 1))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            VStack(alignment: .leading, spacing: 15) {
                                Label("Top Distractions", systemImage: "bolt.slash.fill").font(.title3).bold().foregroundColor(.orange)
                                ForEach(getTopDistractions(), id: \.id) { item in
                                    HStack(spacing: 12) {
                                        AppIconView(appName: item.app, bundleId: nil, size: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.app).font(.subheadline).bold()
                                            Text(item.title).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Text(item.dur.formatHMS()).font(.system(.subheadline, design: .monospaced)).bold()
                                    }.padding(12).background(.ultraThinMaterial.opacity(0.4)).cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.15), lineWidth: 1))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }.padding(40)
            }.scrollContentBackground(.hidden)
        }
    }
    struct ProductivityBucket: Identifiable { var id: String { label }; let label: String; let sortKey: Int; var prod: TimeInterval = 0; var unprod: TimeInterval = 0 }
    struct DistAgg: Identifiable { var id: String { "\(app)|\(title)" }; let app: String; let title: String; let dur: TimeInterval; let res: String }
    
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter
    }()
    
    private func getProductivityTimeline() -> [ProductivityBucket] {
        var buckets: [String: ProductivityBucket] = [:]
        let calendar = Calendar.current
        
        for event in events {
            let dur = (event.duration == 0 ? max(0, Date().timeIntervalSince(event.timestamp)) : event.duration)
            
            let label: String
            let sortKey: Int
            
            if timeRange == .today {
                let hour = calendar.component(.hour, from: event.timestamp)
                label = String(format: "%02d:00", hour)
                sortKey = hour
            } else {
                label = Self.dayFormatter.string(from: event.timestamp)
                sortKey = calendar.ordinality(of: .day, in: .era, for: event.timestamp) ?? 0
            }
            
            var b = buckets[label] ?? ProductivityBucket(label: label, sortKey: sortKey)
            if event.isProductive == true { b.prod += dur } else if event.isProductive == false { b.unprod += dur }
            buckets[label] = b
        }
        return buckets.values.sorted { $0.sortKey < $1.sortKey }
    }
    private func getTopProductive() -> [DistAgg] {
        var dict: [String: DistAgg] = [:]
        for event in events where event.isProductive == true {
            let key = "\(event.appName)|\(event.windowTitle)"
            let dur = (event.duration == 0 ? max(0, Date().timeIntervalSince(event.timestamp)) : event.duration)
            let cur = dict[key]
            dict[key] = DistAgg(app: event.appName, title: event.windowTitle, dur: (cur?.dur ?? 0) + dur, res: event.productivityReason ?? "Productive")
        }
        return dict.values.sorted { $0.dur > $1.dur }.prefix(5).map { $0 }
    }
    private func getTopDistractions() -> [DistAgg] {
        var dict: [String: DistAgg] = [:]
        for event in events where event.isProductive == false {
            let key = "\(event.appName)|\(event.windowTitle)"
            let dur = (event.duration == 0 ? max(0, Date().timeIntervalSince(event.timestamp)) : event.duration)
            let cur = dict[key]
            dict[key] = DistAgg(app: event.appName, title: event.windowTitle, dur: (cur?.dur ?? 0) + dur, res: event.productivityReason ?? "Unproductive")
        }
        return dict.values.sorted { $0.dur > $1.dur }.prefix(5).map { $0 }
    }
}

// MARK: - Reusable Glassy UI Elements

struct DashboardWidgetModifier: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .liquidGlass(cornerRadius: 18)
    }
}

extension View {
    func dashboardWidgetStyle(padding: CGFloat = 20) -> some View {
        modifier(DashboardWidgetModifier(padding: padding))
    }

    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 18) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.primary.opacity(0.12), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Capsule())
            .shadow(color: .purple.opacity(0.3), radius: 2, y: 1)
    }
}

struct GlassyButtonStyle: ButtonStyle {
    var color: Color = .primary
    var isProminent: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isProminent
                        ? color.opacity(configuration.isPressed ? 0.35 : (isHovered ? 0.28 : 0.2))
                        : Color.primary.opacity(isHovered ? 0.09 : 0.06))
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .foregroundColor(isProminent ? color : .primary.opacity(0.85))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.12), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct SummaryCard: View {
    var title: String; var value: String; var icon: String; var color: Color
    var subValue: String? = nil
    /// When set, the card shows a live-updating timer: base + elapsed since start.
    /// Only this inner text re-renders every second — the rest of the view stays static.
    var liveTimer: (base: TimeInterval, start: Date)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Subtle color glow in top-right corner
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 90, height: 90)
                .blur(radius: 22)
                .offset(x: 18, y: -18)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                // Icon + title row
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)
                    Text(title)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                // Main value — live or static
                if value == "PRO" {
                    ProBadge()
                } else if let live = liveTimer {
                    // TimelineView re-renders ONLY this text every second.
                    // The parent DashboardOverviewTab is never re-rendered by this.
                    TimelineView(.periodic(from: Date(), by: 1.0)) { ctx in
                        let total = live.base + max(0, ctx.date.timeIntervalSince(live.start))
                        Text(total.formatHMS())
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundColor(.primary)
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                } else {
                    Text(value)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundColor(.primary)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }

                // Sub-value
                if let sub = subValue {
                    Text(sub)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(color.opacity(0.85))
                        .lineLimit(1)
                        .padding(.top, 3)
                }

                Spacer(minLength: 0)

                // Bottom accent line
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.45))
                    .frame(height: 3)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlass(cornerRadius: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material; var blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = material; view.blendingMode = blendingMode; view.state = .active; return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { nsView.material = material; nsView.blendingMode = blendingMode }
}

struct ActivityRow: View {
    var event: ActivityEvent
    @Environment(TrackingService.self) private var trackingService
    @AppStorage("isPro") private var isPro: Bool = false
    var body: some View {
        HStack(spacing: 12) {
            AppIconView(appName: event.appName, bundleId: event.bundleId, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let catColor = event.category?.color {
                        Circle().fill(catColor).frame(width: 6, height: 6)
                    } else {
                        Circle().fill(Color.clear).frame(width: 6, height: 6)
                    }
                    Text(event.appName).font(.system(.subheadline, design: .rounded)).fontWeight(.semibold).lineLimit(1)
                }
                if !event.windowTitle.isEmpty { Text(event.windowTitle).font(.system(.caption2, design: .rounded)).foregroundColor(.secondary).lineLimit(1) }
            }
            Spacer()
            HStack(spacing: 6) {
                if event.duration == 0 {
                    Text(event.timestamp, style: .timer).font(.system(.caption2, design: .monospaced)).foregroundColor(.blue)
                } else {
                    Text(formatAbbreviated(event.duration)).font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isPro && event.isProductive == true ? Color.green.opacity(0.1) : (isPro && event.isProductive == false ? Color.orange.opacity(0.1) : Color.clear))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isPro && event.isProductive == true ? Color.green.opacity(0.3) : (isPro && event.isProductive == false ? Color.orange.opacity(0.3) : Color.clear), lineWidth: 1))
    }
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
    
    private func formatAbbreviated(_ duration: TimeInterval) -> String {
        return Self.formatter.string(from: duration) ?? "0s"
    }
}

class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]
    private var accessOrder: [String] = []
    private let maxSize = 200

    @MainActor
    func getIcon(appName: String, bundleId: String?) -> NSImage? {
        let key = bundleId ?? appName
        if let cached = cache[key] {
            accessOrder.removeAll { $0 == key }
            accessOrder.append(key)
            return cached
        }

        let workspace = NSWorkspace.shared
        var icon: NSImage?
        if let bId = bundleId, let url = workspace.urlForApplication(withBundleIdentifier: bId) {
            icon = workspace.icon(forFile: url.path)
        } else if let path = workspace.fullPath(forApplication: appName) {
            icon = workspace.icon(forFile: path)
        }

        if let icon = icon {
            cache[key] = icon
            accessOrder.append(key)
            if cache.count > maxSize, let oldest = accessOrder.first {
                accessOrder.removeFirst()
                cache.removeValue(forKey: oldest)
            }
        }
        return icon
    }
}

struct AppIconView: View {
    var appName: String; var bundleId: String?; var size: CGFloat
    var body: some View {
        if let image = AppIconCache.shared.getIcon(appName: appName, bundleId: bundleId) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size) }
        else { Image(systemName: "macwindow").resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size).foregroundColor(.secondary) }
    }
}

struct EventDetailView: View {
    var event: ActivityEvent
    @Environment(TrackingService.self) private var trackingService
    @AppStorage("ai_share_window_titles") private var shareWindowTitles: Bool = false
    @AppStorage("isPro") private var isPro: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 15) {
                AppIconView(appName: event.appName, bundleId: event.bundleId, size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.appName).font(.system(.title, design: .rounded)).bold()
                    HStack(spacing: 6) {
                        if let cat = event.category {
                            HStack(spacing: 4) {
                                Circle().fill(cat.color).frame(width: 8, height: 8)
                                Text(cat.name).foregroundColor(.primary)
                            }
                            Text("•").foregroundColor(.secondary.opacity(0.5))
                        }
                        Text(event.timestamp.formatted(date: .abbreviated, time: .shortened)).foregroundColor(.secondary)
                    }
                }
            }
            Divider().opacity(0.1)
            VStack(alignment: .leading, spacing: 6) { 
                Text("WINDOW TITLE").font(.system(.caption, design: .rounded)).fontWeight(.bold).foregroundColor(.secondary)
                
                if !isPro && event.windowTitle.isEmpty {
                    HStack(spacing: 8) {
                        ProBadge()
                        Text("Required for Window Titles").font(.system(.subheadline, design: .rounded)).foregroundColor(.secondary)
                    }
                } else {
                    let titleText: String = {
                        if !event.windowTitle.isEmpty { return event.windowTitle }
                        if !shareWindowTitles { return "Hidden by privacy settings" }
                        return "No active title"
                    }()
                    
                    let isPlaceholder = event.windowTitle.isEmpty
                    
                    Text(titleText)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(isPlaceholder ? .secondary : .primary)
                }
            }
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DURATION").font(.system(.caption, design: .rounded)).fontWeight(.bold).foregroundColor(.secondary)
                    let duration = (event.duration == 0 ? max(0, Date().timeIntervalSince(event.timestamp)) : event.duration)
                    Text(duration.formatHMS()).font(.system(.title3, design: .monospaced)).bold()
                }
                
                if isPro {
                    if let isProd = event.isProductive {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ASSESSMENT").font(.system(.caption, design: .rounded)).fontWeight(.bold).foregroundColor(.secondary)
                            Label(isProd ? "Productive" : "Unproductive", systemImage: isProd ? "checkmark.seal.fill" : "exclamationmark.octagon.fill").foregroundColor(isProd ? .green : .orange).font(.headline)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ASSESSMENT").font(.system(.caption, design: .rounded)).fontWeight(.bold).foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            ProBadge()
                            Text("Required for AI Rating").font(.system(.subheadline, design: .rounded)).foregroundColor(.secondary)
                        }
                    }
                }
            }
            if isPro {
                if let reason = event.productivityReason { VStack(alignment: .leading, spacing: 6) { Text("AI REASONING").font(.system(.caption, design: .rounded)).fontWeight(.bold).foregroundColor(.secondary); Text(reason).font(.system(.subheadline, design: .rounded)).foregroundColor(.secondary) } }
            }
            Spacer()
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity).background(.thinMaterial).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.2), lineWidth: 1))
    }
}

struct AISettingsView: View {
    @State private var apiKey: String = ""
    @AppStorage("ai_share_window_titles") private var shareWindowTitles: Bool = false
    @AppStorage("isPro") private var isPro: Bool = false
    @State private var showWindowTitlePrivacyAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Settings").font(.system(.largeTitle, design: .rounded)).bold()
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 8) {
                                    Text("FocusGuard").font(.headline)
                                    if isPro { ProBadge() }
                                }
                                Spacer()
                                Toggle("", isOn: $isPro).labelsHidden()
                            }
                            Text(isPro ? "You have access to all premium features." : "Unlock deep AI analysis, productivity scoring, and automatic categorization.").font(.subheadline).foregroundColor(.secondary)
                        }.padding(.vertical, 10)
                    } header: { Label("Subscription", systemImage: "star.fill") }

                    Section {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Gemini API Key").font(.headline)
                            SecureField("Enter Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 450)
                                .onChange(of: apiKey) { _, newValue in
                                    if newValue.isEmpty {
                                        KeychainHelper.delete(key: "gemini_api_key")
                                    } else {
                                        KeychainHelper.save(key: "gemini_api_key", value: newValue)
                                    }
                                }
                            Text("Stored securely in the system Keychain.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }.padding(.vertical, 10)
                    } header: { Label("Security", systemImage: "key.viewfinder") }

                    Section {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                Toggle("Deep Analysis (Window Titles)", isOn: Binding(
                                    get: { shareWindowTitles },
                                    set: { newValue in
                                        if newValue { showWindowTitlePrivacyAlert = true }
                                        else { shareWindowTitles = false }
                                    }
                                )).font(.headline)
                                if !isPro { ProBadge() }
                            }
                            Text("Window titles will be sent to Google's Gemini API for analysis. This may include sensitive content from browser tabs or documents.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }.padding(.vertical, 10)
                    } header: { Label("Privacy", systemImage: "hand.raised.fill") }
                    .disabled(!isPro)
                }.formStyle(.grouped).frame(minHeight: 500).scrollContentBackground(.hidden)
            }.padding(40)
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            KeychainHelper.migrateFromUserDefaults(key: "gemini_api_key")
            apiKey = KeychainHelper.load(key: "gemini_api_key") ?? ""
        }
        .alert("Privacy Notice", isPresented: $showWindowTitlePrivacyAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Enable", role: .destructive) { shareWindowTitles = true }
        } message: {
            Text("Window titles will be sent to Google's Gemini API. This may include sensitive data such as browser tab names, document titles, or other personal information. Data leaves your device.")
        }
    }
}

struct PremiumLockView: View {
    var title: String
    var description: String
    @AppStorage("isPro") private var isPro: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 46))
                .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .purple.opacity(0.3), radius: 10, y: 5)
            
            Text(title).font(.system(.title2, design: .rounded)).bold()
            
            Text(description)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 280)
            
            Button(action: {
                withAnimation { isPro = true }
            }) {
                Text("Unlock Pro")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(30)
        .background(.thinMaterial)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.2), lineWidth: 1))
    }
}

struct WidgetSizeClassKey: LayoutValueKey {
    static let defaultValue: DashboardWidget.SizeClass = .small
}

extension View {
    func widgetSizeClass(_ sizeClass: DashboardWidget.SizeClass) -> some View {
        layoutValue(key: WidgetSizeClassKey.self, value: sizeClass)
    }
}

struct DashboardSmartLayout: Layout {
    var spacing: CGFloat = 20
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = calculate(in: proposal.width ?? 0, subviews: subviews)
        return result.bounds
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = calculate(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let rect = result.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                proposal: ProposedViewSize(width: rect.width, height: rect.height)
            )
        }
    }
    
    struct LayoutResult {
        var bounds: CGSize
        var frames: [CGRect]
    }
    
    private func calculate(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
        var frames: [CGRect] = []
        let W = maxWidth
        let halfW = max(0, (W - spacing) / 2)
        let thirdW = max(0, (W - spacing * 2) / 3)
        
        var currentY: CGFloat = 0
        var i = 0
        
        while i < subviews.count {
            let s0 = subviews[i][WidgetSizeClassKey.self]
            let s1 = i+1 < subviews.count ? subviews[i+1][WidgetSizeClassKey.self] : nil
            let s2 = i+2 < subviews.count ? subviews[i+2][WidgetSizeClassKey.self] : nil
            let s3 = i+3 < subviews.count ? subviews[i+3][WidgetSizeClassKey.self] : nil
            
            if s0 == .large {
                if s1 == .medium || s1 == .large {
                    frames.append(CGRect(x: 0, y: currentY, width: halfW, height: 400))
                    frames.append(CGRect(x: halfW + spacing, y: currentY, width: halfW, height: 400))
                    currentY += 400 + spacing
                    i += 2
                    continue
                }
                if s1 == .small {
                    frames.append(CGRect(x: 0, y: currentY, width: halfW, height: 400))
                    frames.append(CGRect(x: halfW + spacing, y: currentY, width: halfW, height: 120))
                    currentY += 400 + spacing
                    i += 2
                    continue
                }
                frames.append(CGRect(x: 0, y: currentY, width: W, height: 400))
                currentY += 400 + spacing
                i += 1
                continue
            }
            
            if s0 == .medium {
                if s1 == .small && s2 == .small && s3 == .small {
                    frames.append(CGRect(x: 0, y: currentY, width: halfW, height: 400))
                    frames.append(CGRect(x: halfW + spacing, y: currentY, width: halfW, height: 120))
                    frames.append(CGRect(x: halfW + spacing, y: currentY + 140, width: halfW, height: 120))
                    frames.append(CGRect(x: halfW + spacing, y: currentY + 280, width: halfW, height: 120))
                    currentY += 400 + spacing
                    i += 4
                    continue
                }
                if s1 == .medium || s1 == .large {
                    frames.append(CGRect(x: 0, y: currentY, width: halfW, height: 400))
                    frames.append(CGRect(x: halfW + spacing, y: currentY, width: halfW, height: 400))
                    currentY += 400 + spacing
                    i += 2
                    continue
                }
                if s1 == .small {
                    frames.append(CGRect(x: 0, y: currentY, width: halfW, height: 400))
                    frames.append(CGRect(x: halfW + spacing, y: currentY, width: halfW, height: 120))
                    currentY += 400 + spacing
                    i += 2
                    continue
                }
                frames.append(CGRect(x: 0, y: currentY, width: halfW, height: 400))
                currentY += 400 + spacing
                i += 1
                continue
            }
            
            if s0 == .small {
                if s1 == .small && s2 == .small && s3 == .medium {
                    frames.append(CGRect(x: 0, y: currentY, width: halfW, height: 120))
                    frames.append(CGRect(x: 0, y: currentY + 140, width: halfW, height: 120))
                    frames.append(CGRect(x: 0, y: currentY + 280, width: halfW, height: 120))
                    frames.append(CGRect(x: halfW + spacing, y: currentY, width: halfW, height: 400))
                    currentY += 400 + spacing
                    i += 4
                    continue
                }
                if s1 == .small && s2 == .small {
                    frames.append(CGRect(x: 0, y: currentY, width: thirdW, height: 120))
                    frames.append(CGRect(x: thirdW + spacing, y: currentY, width: thirdW, height: 120))
                    frames.append(CGRect(x: thirdW * 2 + spacing * 2, y: currentY, width: thirdW, height: 120))
                    currentY += 120 + spacing
                    i += 3
                    continue
                }
                if s1 == .medium || s1 == .large {
                    frames.append(CGRect(x: 0, y: currentY, width: halfW, height: 120))
                    frames.append(CGRect(x: halfW + spacing, y: currentY, width: halfW, height: 400))
                    currentY += 400 + spacing
                    i += 2
                    continue
                }
                if s1 == .small {
                    frames.append(CGRect(x: 0, y: currentY, width: halfW, height: 120))
                    frames.append(CGRect(x: halfW + spacing, y: currentY, width: halfW, height: 120))
                    currentY += 120 + spacing
                    i += 2
                    continue
                }
                frames.append(CGRect(x: 0, y: currentY, width: W, height: 120))
                currentY += 120 + spacing
                i += 1
                continue
            }
        }
        
        return LayoutResult(bounds: CGSize(width: W, height: max(0, currentY - spacing)), frames: frames)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.bounds
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.frames[index].origin
            subview.place(at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY), proposal: .unspecified)
        }
    }
    struct FlowResult {
        var bounds: CGSize = .zero; var frames: [CGRect] = []
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0; var currentY: CGFloat = 0; var lineHeight: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if currentX + size.width > maxWidth && currentX > 0 { currentX = 0; currentY += lineHeight + spacing; lineHeight = 0 }
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                currentX += size.width + spacing; lineHeight = max(lineHeight, size.height)
            }
            bounds = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
