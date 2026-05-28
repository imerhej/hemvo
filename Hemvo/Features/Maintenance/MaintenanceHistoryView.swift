//  MaintenanceHistoryView.swift
//  Hemvo
//  Shows all completed maintenance tasks with area filter, edit, and delete.

internal import SwiftUI
internal import Combine

struct MaintenanceHistoryView: View {

    @ObservedObject var vm: MaintenanceViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedArea: MaintenanceItem.HomeArea? = nil
    @State private var taskToDelete: CompletedTask? = nil
    @State private var showDeleteAlert = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private let amber   = Color(hex: "#C8922A")!
    private let amberBg = Color(hex: "#F5E4C3")!
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let divider = Color(hex: "#E6DDD0")!
    private let cream   = Color(hex: "#FAF7F2")!
    private let green   = Color(hex: "#3D7A52")!

    private var filtered: [CompletedTask] {
        var list = vm.history
        if let area = selectedArea { list = list.filter { $0.area == area } }
        if !searchText.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return list.sorted { $0.completedDate > $1.completedDate }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()
                VStack(spacing: 0) {
                    // ── Header ───────────────────────────────
                    historyHeader

                    // ── Search ───────────────────────────────
                    searchBar

                    // ── Area filter ──────────────────────────
                    areaFilter

                    // ── List ─────────────────────────────────
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 10) {
                                ForEach(filtered) { task in
                                    HistoryTaskCard(
                                        task:      task,
                                        canDelete: vm.canDeleteHistory(task),
                                        onDelete:  { taskToDelete = task; showDeleteAlert = true }
                                    )
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .alert("Delete Record", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let t = taskToDelete { vm.deleteHistory(t) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Remove \(taskToDelete?.title ?? "") from history?")
            }
        }
    }

    // MARK: - Header
    private var historyHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#2C4A2E")!, Color(hex: "#3D7A52")!],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea(edges: .top)

            Circle().fill(Color.white.opacity(0.06)).frame(width: 160).offset(x: 140, y: -30)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("COMPLETED")
                            .font(.system(size: 9, weight: .heavy)).kerning(3)
                            .foregroundColor(.white.opacity(0.7))
                        Text("History")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14)

                // Stats row
                HStack(spacing: 0) {
                    historyStat(value: vm.history.count,  label: "Total Done")
                    Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 28)
                    historyStat(value: thisWeekCount,  label: "This Week")
                    Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 28)
                    historyStat(value: thisMonthCount, label: "This Month")
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .frame(height: 148)
    }

    private func historyStat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 18, weight: .black)).foregroundColor(.white)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
    }

    private var thisWeekCount: Int {
        let start = Calendar.current.date(from: Calendar.current.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return vm.history.filter { $0.completedDate >= start }.count
    }
    private var thisMonthCount: Int {
        vm.history.filter {
            Calendar.current.isDate($0.completedDate, equalTo: Date(), toGranularity: .month)
        }.count
    }

    // MARK: - Search bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(muted)
                TextField("Search history…", text: $searchText)
                    .font(.system(size: 14)).foregroundColor(brown)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(muted)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(divider, lineWidth: 1))
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Color.white)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    // MARK: - Area filter
    private var areaFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                areaChip(title: "All", icon: "square.grid.2x2.fill", isSelected: selectedArea == nil) {
                    withAnimation { selectedArea = nil }
                }
                ForEach(MaintenanceItem.HomeArea.allCases) { area in
                    let count = vm.history.filter { $0.area == area }.count
                    if count > 0 {
                        areaChip(title: "\(area.rawValue) (\(count))",
                                 icon: area.iconName,
                                 isSelected: selectedArea == area) {
                            withAnimation { selectedArea = selectedArea == area ? nil : area }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func areaChip(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(isSelected ? .white : muted)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? green : Color(hex: "#F5F0EB")!)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected ? green : divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(Color(hex: "#E8F5E9")!).frame(width: 100, height: 100)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40)).foregroundColor(green)
            }
            VStack(spacing: 8) {
                Text(vm.history.isEmpty ? "No History Yet" : "No Results")
                    .font(.system(size: 22, weight: .black)).foregroundColor(brown)
                Text(vm.history.isEmpty
                     ? "Completed tasks will appear here."
                     : "Try a different filter or search term.")
                    .font(.system(size: 14, weight: .medium)).foregroundColor(muted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - HistoryTaskCard
struct HistoryTaskCard: View {
    let task:      CompletedTask
    let canDelete: Bool
    let onDelete:  () -> Void

    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let amber   = Color(hex: "#C8922A")!
    private let amberBg = Color(hex: "#F5E4C3")!
    private let divider = Color(hex: "#E6DDD0")!
    private let green   = Color(hex: "#3D7A52")!
    private let greenBg = Color(hex: "#E8F5E9")!

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Area icon (green tint — completed)
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(greenBg).frame(width: 50, height: 50)
                    Image(systemName: task.area.iconName)
                        .font(.system(size: 20, weight: .semibold)).foregroundColor(green)
                }

                // Info
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .bold)).foregroundColor(brown).lineLimit(2)

                    HStack(spacing: 6) {
                        Text(task.area.rawValue)
                            .font(.system(size: 10, weight: .heavy)).kerning(0.3).foregroundColor(muted)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(hex: "#F5F0EB")!).cornerRadius(20)
                        Text(task.frequency.rawValue)
                            .font(.system(size: 10, weight: .heavy)).kerning(0.3).foregroundColor(amber)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(amberBg).cornerRadius(20)
                    }
                }

                Spacer()

                // Checkmark badge
                ZStack {
                    Circle().fill(greenBg).frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .black)).foregroundColor(green)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            // ── Completed date row ────────────────────────
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundColor(green)
                Text("Completed \(task.completedDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(green)

                Spacer()

                // Was due
                Text("Was due \(task.nextDue.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(muted)
            }
            .padding(.horizontal, 16).padding(.bottom, 10)

            divider.frame(height: 1).padding(.horizontal, 16)

            // ── Bottom row: time + edit + delete ─────────
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "timer").font(.system(size: 10))
                    Text("\(task.estimatedMinutes)m").font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(muted)

                if !task.notes.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "note.text").font(.system(size: 10))
                        Text(task.notes).font(.system(size: 11)).lineLimit(1)
                    }
                    .foregroundColor(muted)
                }

                Spacer()

                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.red.opacity(0.7))
                            .frame(width: 28, height: 28).background(Color.red.opacity(0.07)).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Color.white)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(green.opacity(0.15), lineWidth: 1))
        .shadow(color: Color(hex: "#1A1208")!.opacity(0.04), radius: 6, y: 2)
    }
}

#Preview { MaintenanceHistoryView(vm: MaintenanceViewModel()) }
