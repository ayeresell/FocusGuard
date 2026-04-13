//
//  SettingsView.swift
//  FocusGuard
//

import SwiftUI
import SwiftData
import OSLog

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var categories: [Category]
    
    @State private var selectedCategoryId: UUID?
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryColor = Color.blue
    @State private var showingResetAlert = false

    var body: some View {
        HStack(spacing: 0) {
            // Categories List (Inner Sidebar)
            VStack(spacing: 0) {
                List(selection: $selectedCategoryId) {
                    ForEach(categories) { category in
                        HStack {
                            Circle()
                                .fill(category.color)
                                .frame(width: 10, height: 10)
                            Text(category.name)
                                .font(.subheadline)
                        }
                        .tag(category.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(category)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteCategories)
                }
                .listStyle(.sidebar)
                
                Divider()
                
                // Toolbar for categories
                HStack(spacing: 12) {
                    Button(action: { showingResetAlert = true }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(GlassyButtonStyle())
                    .help("Reset to defaults")
                    
                    Spacer()
                    
                    Button(action: { showingAddCategory = true }) {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(GlassyButtonStyle(color: .blue, isProminent: true))
                }
                .padding(10)
                .background(.ultraThinMaterial)
            }
            .frame(width: 200)
            
            Divider()
            
            // Category Detail Area
            Group {
                if let id = selectedCategoryId, let category = categories.first(where: { $0.id == id }) {
                    CategoryDetailView(category: category)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Select a category to edit rules")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        }
        .alert("Reset Categories", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                withAnimation { resetToDefaultCategories() }
            }
        } message: {
            Text("This will restore default categories and delete all custom rules.")
        }
        .sheet(isPresented: $showingAddCategory) {
            VStack(spacing: 20) {
                Text("New Category").font(.headline)
                TextField("Name (e.g. Work)", text: $newCategoryName).textFieldStyle(.roundedBorder)
                ColorPicker("Category Color", selection: $newCategoryColor)
                HStack {
                    Button("Cancel") { showingAddCategory = false }
                    Spacer()
                    Button("Add Category") { addCategory() }
                        .buttonStyle(.borderedProminent)
                        .disabled(newCategoryName.isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }
    
    private func addCategory() {
        let nsColor = NSColor(newCategoryColor)
        var hex = "#0000FF"
        if let cgColor = nsColor.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
           let components = cgColor.components, components.count >= 3 {
            let r = Float(components[0]); let g = Float(components[1]); let b = Float(components[2])
            hex = String(format: "#%02X%02X%02X", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
        let category = Category(name: newCategoryName, colorHex: hex)
        modelContext.insert(category)
        newCategoryName = ""; showingAddCategory = false
    }
    
    private func deleteCategories(offsets: IndexSet) {
        for index in offsets { modelContext.delete(categories[index]) }
    }
    
    private func resetToDefaultCategories() {
        for category in categories { modelContext.delete(category) }
        let defaults: [(String, String)] = [
            ("Software Development", "#3498db"), ("Communication & Chat", "#e74c3c"),
            ("Web Browsing & Research", "#2ecc71"), ("Entertainment & Media", "#9b59b6"),
            ("Productivity & Office", "#f1c40f"), ("System & Utilities", "#95a5a6"),
            ("Design & Creativity", "#e67e22"), ("Other", "#bdc3c7")
        ]
        for def in defaults {
            let cat = Category(name: def.0, colorHex: def.1)
            modelContext.insert(cat)
        }
        do {
            try modelContext.save()
        } catch {
            Logger().error("FocusGuard: Failed to save after reset: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: NSNotification.Name("RulesDidUpdate"), object: nil)
    }
}

struct CategoryDetailView: View {
    @Bindable var category: Category
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var newPattern = ""
    @State private var newMatchType: MatchType = .contains

    private var regexError: String? {
        guard newMatchType == .regex, !newPattern.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: newPattern, options: .caseInsensitive)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 16) {
                ColorPicker("", selection: Binding(
                    get: { category.color },
                    set: { newColor in
                        let nsColor = NSColor(newColor)
                        if let cgColor = nsColor.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
                           let components = cgColor.components, components.count >= 3 {
                            let r = Float(components[0]); let g = Float(components[1]); let b = Float(components[2])
                            category.colorHex = String(format: "#%02X%02X%02X", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
                            do { try modelContext.save() } catch { Logger().error("FocusGuard: Failed to save: \(error.localizedDescription)") }
                        }
                    }
                )).labelsHidden()
                
                TextField("Category Name", text: Binding(
                    get: { category.name },
                    set: { category.name = $0; do { try modelContext.save() } catch { Logger().error("FocusGuard: Failed to save: \(error.localizedDescription)") } }
                ))
                .font(.system(.title, design: .rounded)).bold()
                .textFieldStyle(.plain)
                
                Spacer()
                Button(role: .destructive) {
                    modelContext.delete(category)
                } label: {
                    Label("Delete Category", systemImage: "trash")
                }
                .buttonStyle(GlassyButtonStyle(color: .red))
            }
            
            Divider().opacity(0.5)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Matching Rules").font(.system(.title3, design: .rounded)).bold()
                Text("Apps or window titles matching these rules will be assigned to this category.").font(.caption).foregroundColor(.secondary)
            }
            
            ScrollView {
                VStack(spacing: 6) {
                    if let rules = category.rules, !rules.isEmpty {
                        ForEach(rules) { rule in
                            HStack(spacing: 12) {
                                Text(rule.pattern)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text(rule.matchTypeRaw)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(4)
                                    .foregroundColor(.secondary)
                                
                                Button(role: .destructive) {
                                    deleteRule(rule)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 16, height: 16)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    if hovering { NSCursor.pointingHand.push() }
                                    else { NSCursor.pop() }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.05), lineWidth: 1))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15), lineWidth: 0.5))
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.largeTitle)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No rules configured")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(.ultraThinMaterial.opacity(0.5))
                        .cornerRadius(12)
                    }
                }
                .padding(.bottom, 4)
                .padding(.trailing, 8)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Add New Rule").font(.system(.subheadline, design: .rounded)).bold()
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Match Type").font(.caption2).foregroundColor(.secondary)
                        Picker("", selection: $newMatchType) {
                            ForEach(MatchType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pattern").font(.caption2).foregroundColor(.secondary)
                        TextField("e.g. Google Chrome", text: $newPattern)
                            .textFieldStyle(.roundedBorder)
                        if let error = regexError {
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                    }
                    Button(action: addRule) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(GlassyButtonStyle(color: .blue, isProminent: true))
                    .disabled(newPattern.isEmpty || regexError != nil)
                }
            }
            .padding(16)
            .background(.thinMaterial)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.1), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
        .padding(30)
    }
    
    private func addRule() {
        let rule = CategoryRule(pattern: newPattern, matchType: newMatchType)
        rule.category = category; modelContext.insert(rule)
        if category.rules == nil { category.rules = [] }
        category.rules?.append(rule); newPattern = ""
        NotificationCenter.default.post(name: NSNotification.Name("RulesDidUpdate"), object: nil)
    }
    
    private func deleteRule(_ rule: CategoryRule) {
        withAnimation {
            category.rules?.removeAll(where: { $0.id == rule.id })
            modelContext.delete(rule)
            NotificationCenter.default.post(name: NSNotification.Name("RulesDidUpdate"), object: nil)
        }
    }
    private func deleteRules(offsets: IndexSet) {
        withAnimation {
            guard let rules = category.rules else { return }
            for index in offsets {
                let rule = rules[index]
                category.rules?.remove(at: index)
                modelContext.delete(rule)
            }
            NotificationCenter.default.post(name: NSNotification.Name("RulesDidUpdate"), object: nil)
        }
    }
}
