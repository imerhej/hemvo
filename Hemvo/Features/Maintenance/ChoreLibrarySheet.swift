
//  ChoreLibrarySheet.swift
//  Hemvo
//  Browse age-appropriate chore templates and auto-fill AddMaintenanceTaskSheet.

internal import SwiftUI

// MARK: - ChoreLibrary

enum ChoreLibrary {
    static let all: [ChoreTemplate] = [
        // Easy — suitable for teens and up
        ChoreTemplate(id: "e01", title: "Put toys away",                area: .general,  frequency: .daily,     difficulty: .easy,   estimatedMinutes: 5),
        ChoreTemplate(id: "e02", title: "Put dirty clothes in hamper",  area: .bedroom,  frequency: .daily,     difficulty: .easy,   estimatedMinutes: 5),
        ChoreTemplate(id: "e03", title: "Help set the table",           area: .kitchen,  frequency: .daily,     difficulty: .easy,   estimatedMinutes: 5),
        ChoreTemplate(id: "e04", title: "Feed pets",                    area: .general,  frequency: .daily,     difficulty: .easy,   estimatedMinutes: 5),
        ChoreTemplate(id: "e05", title: "Make bed",                     area: .bedroom,  frequency: .daily,     difficulty: .easy,   estimatedMinutes: 5),
        ChoreTemplate(id: "e06", title: "Clear dinner table",           area: .kitchen,  frequency: .daily,     difficulty: .easy,   estimatedMinutes: 5),
        ChoreTemplate(id: "e07", title: "Water indoor plants",          area: .general,  frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 10),
        ChoreTemplate(id: "e08", title: "Dust low surfaces",            area: .general,  frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 10),
        ChoreTemplate(id: "e09", title: "Sweep kitchen floor",          area: .kitchen,  frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 10),
        ChoreTemplate(id: "e10", title: "Wipe bathroom sink",           area: .bathroom, frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 5),
        ChoreTemplate(id: "e11", title: "Sort laundry by color",        area: .general,  frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 10),
        ChoreTemplate(id: "e12", title: "Fold and put away laundry",    area: .bedroom,  frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 15),
        ChoreTemplate(id: "e13", title: "Take out recycling",           area: .general,  frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 5),
        ChoreTemplate(id: "e14", title: "Water outdoor plants",         area: .yard,     frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 10),
        ChoreTemplate(id: "e15", title: "Vacuum small areas",           area: .general,  frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 10),
        ChoreTemplate(id: "e16", title: "Carry in light groceries",     area: .general,  frequency: .weekly,    difficulty: .easy,   estimatedMinutes: 5),

        // Medium — suitable for teens and up (ages 10+)
        ChoreTemplate(id: "m01", title: "Load/unload dishwasher",       area: .kitchen,  frequency: .daily,     difficulty: .medium, estimatedMinutes: 10),
        ChoreTemplate(id: "m02", title: "Wash dishes by hand",          area: .kitchen,  frequency: .daily,     difficulty: .medium, estimatedMinutes: 15),
        ChoreTemplate(id: "m03", title: "Cook simple meals",            area: .kitchen,  frequency: .weekly,    difficulty: .medium, estimatedMinutes: 20),
        ChoreTemplate(id: "m04", title: "Cook full family meals",       area: .kitchen,  frequency: .weekly,    difficulty: .medium, estimatedMinutes: 45),
        ChoreTemplate(id: "m05", title: "Mop floors",                   area: .general,  frequency: .weekly,    difficulty: .medium, estimatedMinutes: 20),
        ChoreTemplate(id: "m06", title: "Clean bathroom",               area: .bathroom, frequency: .weekly,    difficulty: .medium, estimatedMinutes: 25),
        ChoreTemplate(id: "m07", title: "Vacuum whole house",           area: .general,  frequency: .weekly,    difficulty: .medium, estimatedMinutes: 30),
        ChoreTemplate(id: "m08", title: "Take trash to curb",           area: .general,  frequency: .weekly,    difficulty: .medium, estimatedMinutes: 5),
        ChoreTemplate(id: "m09", title: "Wash and fold laundry",        area: .general,  frequency: .weekly,    difficulty: .medium, estimatedMinutes: 45),
        ChoreTemplate(id: "m10", title: "Rake leaves",                  area: .yard,     frequency: .monthly,   difficulty: .medium, estimatedMinutes: 30),
        ChoreTemplate(id: "m11", title: "Mow lawn",                     area: .yard,     frequency: .weekly,    difficulty: .medium, estimatedMinutes: 45),
        ChoreTemplate(id: "m12", title: "Weed garden",                  area: .yard,     frequency: .weekly,    difficulty: .medium, estimatedMinutes: 30),
        ChoreTemplate(id: "m13", title: "Help with grocery shopping",   area: .general,  frequency: .weekly,    difficulty: .medium, estimatedMinutes: 30),
        ChoreTemplate(id: "m14", title: "Deep clean bedroom",           area: .bedroom,  frequency: .monthly,   difficulty: .medium, estimatedMinutes: 30),

        // Hard — adult-level tasks (ages 16+)
        ChoreTemplate(id: "h01", title: "Mow and edge lawn",            area: .yard,     frequency: .weekly,    difficulty: .hard,   estimatedMinutes: 60),
        ChoreTemplate(id: "h02", title: "Wash car",                     area: .garage,   frequency: .monthly,   difficulty: .hard,   estimatedMinutes: 45),
        ChoreTemplate(id: "h03", title: "Change air filter",            area: .hvac,     frequency: .quarterly, difficulty: .hard,   estimatedMinutes: 15),
        ChoreTemplate(id: "h04", title: "Deep clean kitchen",           area: .kitchen,  frequency: .monthly,   difficulty: .hard,   estimatedMinutes: 60),
        ChoreTemplate(id: "h05", title: "Deep clean bathrooms",         area: .bathroom, frequency: .monthly,   difficulty: .hard,   estimatedMinutes: 45),
        ChoreTemplate(id: "h06", title: "Clean dryer vent",             area: .general,  frequency: .quarterly, difficulty: .hard,   estimatedMinutes: 30),
        ChoreTemplate(id: "h07", title: "Trim trees and bushes",        area: .yard,     frequency: .monthly,   difficulty: .hard,   estimatedMinutes: 60),
        ChoreTemplate(id: "h08", title: "Plan and cook weekly meals",   area: .kitchen,  frequency: .weekly,    difficulty: .hard,   estimatedMinutes: 60),
        ChoreTemplate(id: "h09", title: "Manage household grocery list",area: .general,  frequency: .weekly,    difficulty: .hard,   estimatedMinutes: 15),
        ChoreTemplate(id: "h10", title: "Inspect and clean gutters",    area: .general,  frequency: .quarterly, difficulty: .hard,   estimatedMinutes: 60),
        ChoreTemplate(id: "h11", title: "Deep clean entire house",      area: .general,  frequency: .monthly,   difficulty: .hard,   estimatedMinutes: 120),
        ChoreTemplate(id: "h12", title: "Handle all lawn care",         area: .yard,     frequency: .weekly,    difficulty: .hard,   estimatedMinutes: 90),
    ]

    static func filtered(maxDifficulty: MaintenanceItem.Difficulty) -> [ChoreTemplate] {
        switch maxDifficulty {
        case .easy:   return all.filter { $0.difficulty == .easy }
        case .medium: return all.filter { $0.difficulty == .easy || $0.difficulty == .medium }
        case .hard:   return all
        }
    }
}

// MARK: - ChoreLibrarySheet

struct ChoreLibrarySheet: View {
    let maxDifficulty: MaintenanceItem.Difficulty
    let onSelect: (ChoreTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var difficultyFilter: MaintenanceItem.Difficulty? = nil
    @State private var searchText: String = ""

    private let amber   = Color(hex: "#C8922A")!
    private let amberBg = Color(hex: "#F5E4C3")!
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let divider = Color(hex: "#E6DDD0")!
    private let cream   = Color(hex: "#F5F0E8")!

    private var filteredTemplates: [ChoreTemplate] {
        let pool = ChoreLibrary.filtered(maxDifficulty: maxDifficulty)
        let byDifficulty = difficultyFilter == nil ? pool : pool.filter { $0.difficulty == difficultyFilter }
        guard !searchText.isEmpty else { return byDifficulty }
        return byDifficulty.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var groupedTemplates: [(MaintenanceItem.HomeArea, [ChoreTemplate])] {
        let grouped = Dictionary(grouping: filteredTemplates, by: \.area)
        return MaintenanceItem.HomeArea.allCases
            .compactMap { area in
                guard let items = grouped[area], !items.isEmpty else { return nil }
                return (area, items)
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()
                VStack(spacing: 0) {
                    difficultyFilterBar
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    if groupedTemplates.isEmpty {
                        emptyState
                    } else {
                        choreList
                    }
                }
            }
            .navigationTitle("Chore Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chores…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(amber)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    private var difficultyFilterBar: some View {
        HStack(spacing: 8) {
            filterPill(label: "All", color: brown, selected: difficultyFilter == nil) {
                difficultyFilter = nil
            }
            ForEach(availableFilters) { diff in
                let diffColor = Color(hex: diff.colorHex)!
                filterPill(label: diff.rawValue, color: diffColor, selected: difficultyFilter == diff) {
                    difficultyFilter = difficultyFilter == diff ? nil : diff
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availableFilters: [MaintenanceItem.Difficulty] {
        switch maxDifficulty {
        case .easy:   return [.easy]
        case .medium: return [.easy, .medium]
        case .hard:   return MaintenanceItem.Difficulty.allCases
        }
    }

    private func filterPill(label: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selected ? .white : color)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? color : color.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    private var choreList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(groupedTemplates, id: \.0) { area, templates in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: area.iconName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(muted)
                            Text(area.rawValue.uppercased())
                                .font(.system(size: 10, weight: .heavy))
                                .kerning(1.2)
                                .foregroundColor(muted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        VStack(spacing: 0) {
                            ForEach(Array(templates.enumerated()), id: \.element.id) { idx, template in
                                Button {
                                    onSelect(template)
                                    dismiss()
                                } label: {
                                    choreRow(template)
                                }
                                .buttonStyle(.plain)

                                if idx < templates.count - 1 {
                                    divider.frame(height: 1).padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(divider, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
    }

    private func choreRow(_ template: ChoreTemplate) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: template.difficulty.colorHex)!.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: template.difficulty.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: template.difficulty.colorHex)!)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(brown)
                HStack(spacing: 6) {
                    difficultyBadge(template.difficulty)
                    Text("·")
                        .foregroundColor(muted)
                        .font(.system(size: 12))
                    Text(template.frequency.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(muted)
                    Text("·")
                        .foregroundColor(muted)
                        .font(.system(size: 12))
                    Text("\(template.estimatedMinutes) min")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(muted)
                }
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(amber.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func difficultyBadge(_ difficulty: MaintenanceItem.Difficulty) -> some View {
        Text(difficulty.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Color(hex: difficulty.colorHex)!)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(hex: difficulty.colorHex)!.opacity(0.12))
            .clipShape(Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(muted.opacity(0.5))
            Text("No chores found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(muted)
            Spacer()
        }
    }
}
