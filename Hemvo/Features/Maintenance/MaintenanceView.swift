//  MaintenanceView.swift
//  Hemvo
//  Redesigned to match screenshot: amber gradient header, 4-stat bar,
//  horizontal area filter chips, task cards, amber Add Task FAB.

internal import SwiftUI
internal import Combine

// MARK: - Palette
private let mvAmber   = Color(hex: "#C8922A")!
private let mvAmberBg = Color(hex: "#F5E4C3")!
private let mvBrown   = Color(hex: "#1A1208")!
private let mvMuted   = Color(hex: "#7A6A55")!
private let mvDivider = Color(hex: "#E6DDD0")!
private let mvCream   = Color(hex: "#F5F0E8")!

struct MaintenanceView: View {

    @StateObject private var vm = MaintenanceViewModel()
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var householdService: HouseholdService

    private var canWrite: Bool {
        guard let uid = authVM.userID?.uuidString,
              let member = householdService.household?.members.first(where: { $0.id == uid })
        else { return true }
        return member.role.canWrite
    }
    @State private var selectedArea:  MaintenanceItem.HomeArea? = nil
    @State private var showAddTask    = false
    @State private var showHistory    = false
    @State private var itemToDelete:  MaintenanceItem? = nil
    @State private var showDeleteAlert = false
    @State private var itemToEdit:    MaintenanceItem? = nil
    @State private var selectedTask:  MaintenanceItem? = nil

    var filteredItems: [MaintenanceItem] {
        let base = selectedArea == nil ? vm.items : vm.items(for: selectedArea!)
        return base.sorted {
            if $0.isOverdue != $1.isOverdue { return $0.isOverdue }
            if $0.isDueSoon != $1.isDueSoon { return $0.isDueSoon }
            return $0.nextDue < $1.nextDue
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                mvCream.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    areaFilterStrip
                    if filteredItems.isEmpty {
                        emptyState
                    } else {
                        taskList
                    }
                }

                // Add Task FAB — owners and adults only
                if canWrite {
                    Button { showAddTask = true } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.25)).frame(width: 22, height: 22)
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.white)
                            }
                            Text("Add Task")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(
                            Capsule().fill(mvAmber)
                                .shadow(color: mvAmber.opacity(0.35), radius: 6, y: 2)
                        )
                    }
                    .padding(.trailing, 16).padding(.bottom, 10)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddTask) {
                AddMaintenanceTaskSheet(vm: vm)
            }
            .sheet(isPresented: $showHistory) {
                MaintenanceHistoryView(vm: vm)
            }
            .sheet(item: $itemToEdit) { item in
                AddMaintenanceTaskSheet(vm: vm, editing: item)
            }
            .sheet(item: $selectedTask) { task in
                MaintenanceTaskDetailSheet(
                    task: task,
                    canWrite: canWrite,
                    vm: vm,
                    itemToEdit: $itemToEdit,
                    itemToDelete: $itemToDelete,
                    showDeleteAlert: $showDeleteAlert,
                    selectedTask: $selectedTask
                )
            }
            .alert("Delete Task", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete { vm.deleteItem(item) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove \"\(itemToDelete?.title ?? "")\"?")
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: "#A0681A")!, mvAmber, Color(hex: "#D4A030")!],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            // Decorative circle
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 220)
                .offset(x: 160, y: -60)

            VStack(alignment: .leading, spacing: 14) {
                // Title row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FIX-IT")
                            .font(.system(size: 11, weight: .heavy)).kerning(2.5)
                            .foregroundColor(.white.opacity(0.75))
                        Text("Maintenance")
                            .font(.system(size: 30, weight: .black))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button { showHistory = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                            Text("History")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(mvAmber)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            Capsule().fill(Color.white.opacity(0.92))
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)

                // Stats row
                HStack(spacing: 0) {
                    statCell(value: vm.overdueItems.count,  label: "Overdue",    color: Color(hex: "#FF6B6B")!)
                    statDivider
                    statCell(value: vm.dueSoonItems.count,  label: "Due Soon",   color: .white)
                    statDivider
                    statCell(value: vm.upToDateItems.count, label: "Up to Date", color: .white)
                    statDivider
                    statCell(value: vm.history.count,       label: "Completed",  color: .white)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .frame(height: 190)
    }

    private func statCell(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 22, weight: .black))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 30)
    }

    // MARK: - Area filter chips
    private var areaFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                areaChip(label: "All", icon: "square.grid.2x2.fill",
                         isSelected: selectedArea == nil) { selectedArea = nil }

                ForEach(MaintenanceItem.HomeArea.allCases) { area in
                    areaChip(label: area.rawValue, icon: area.iconName,
                             isSelected: selectedArea == area) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedArea = selectedArea == area ? nil : area
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) { mvDivider.frame(height: 1) }
    }

    private func areaChip(label: String, icon: String,
                           isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(isSelected ? .white : mvBrown)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                Capsule().fill(isSelected ? mvAmber : Color.white)
                    .shadow(color: isSelected ? mvAmber.opacity(0.3) : Color.black.opacity(0.06),
                            radius: isSelected ? 6 : 3, y: 2)
            )
            .overlay(Capsule().stroke(isSelected ? Color.clear : mvDivider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Task list
    private var taskList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(filteredItems) { item in
                    MaintenanceTaskCard(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedTask = item }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 110)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(mvAmberBg).frame(width: 110, height: 110)
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(mvAmber)
            }
            VStack(spacing: 8) {
                Text("No Tasks Yet")
                    .font(.system(size: 22, weight: .black)).foregroundColor(mvBrown)
                Text("Tap + to add your first\nmaintenance task.")
                    .font(.system(size: 15, weight: .medium)).foregroundColor(mvMuted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - MaintenanceTaskCard
struct MaintenanceTaskCard: View {
    let item: MaintenanceItem

    private var statusColor: Color {
        if item.isOverdue  { return Color(hex: "#C0392B")! }
        if item.isDueSoon  { return Color(hex: "#E67E22")! }
        return Color(hex: "#3D7A52")!
    }

    private var statusBg: Color {
        if item.isOverdue  { return Color(hex: "#C0392B")!.opacity(0.1) }
        if item.isDueSoon  { return Color(hex: "#E67E22")!.opacity(0.1) }
        return Color(hex: "#3D7A52")!.opacity(0.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Area icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(mvAmberBg)
                        .frame(width: 46, height: 46)
                    Image(systemName: item.area.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(mvAmber)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold)).foregroundColor(mvBrown)
                    HStack(spacing: 8) {
                        // Status badge
                        HStack(spacing: 4) {
                            Circle().fill(statusColor).frame(width: 6, height: 6)
                            Text(item.statusLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(statusColor)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(statusBg)
                        .cornerRadius(20)

                        Text(item.area.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(mvMuted)
                    }
                }

                Spacer()
            }

            // Frequency + time + due date row
            HStack(spacing: 12) {
                Label(item.frequency.rawValue, systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(mvMuted)
                Label("\(item.estimatedMinutes) min", systemImage: "clock")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(mvMuted)
                Spacer()
                Label(item.nextDue.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                      systemImage: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(item.isOverdue ? Color(hex: "#C0392B")! : mvMuted)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(mvDivider, lineWidth: 1))
        .shadow(color: mvBrown.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - MaintenanceTaskDetailSheet
struct MaintenanceTaskDetailSheet: View {
    let task: MaintenanceItem
    var canWrite: Bool = true
    @ObservedObject var vm: MaintenanceViewModel
    @Binding var itemToEdit: MaintenanceItem?
    @Binding var itemToDelete: MaintenanceItem?
    @Binding var showDeleteAlert: Bool
    @Binding var selectedTask: MaintenanceItem?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var householdService = HouseholdService.shared
    @State private var showMarkDoneConfirm = false

    private var assignedMembers: [HouseholdMembership] {
        task.assignedMemberIDs.compactMap { id in
            householdService.household?.members.first { $0.id == id }
        }
    }

    private var statusColor: Color {
        if task.isOverdue  { return Color(hex: "#C0392B")! }
        if task.isDueSoon  { return Color(hex: "#E67E22")! }
        return Color(hex: "#3D7A52")!
    }

    private var statusBg: Color {
        if task.isOverdue  { return Color(hex: "#C0392B")!.opacity(0.1) }
        if task.isDueSoon  { return Color(hex: "#E67E22")!.opacity(0.1) }
        return Color(hex: "#3D7A52")!.opacity(0.1)
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                mvCream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        // ── Task header card ───────────────────────────
                        VStack(spacing: 12) {
                            ZStack {
                                Circle().fill(mvAmberBg).frame(width: 72, height: 72)
                                Image(systemName: task.area.iconName)
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundColor(mvAmber)
                            }
                            Text(task.title)
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(mvBrown)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 4) {
                                Circle().fill(statusColor).frame(width: 7, height: 7)
                                Text(task.statusLabel)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(statusColor)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(statusBg)
                            .cornerRadius(20)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(mvDivider, lineWidth: 1))

                        // ── Detail rows ────────────────────────────────
                        VStack(spacing: 0) {
                            detailRow(icon: "calendar", label: "Next Due", value: dateFormatter.string(from: task.nextDue))
                            mvDivider.frame(height: 1).padding(.horizontal, 16)
                            detailRow(icon: "arrow.clockwise", label: "Frequency", value: task.frequency.rawValue)
                            mvDivider.frame(height: 1).padding(.horizontal, 16)
                            detailRow(icon: "house.fill", label: "Area", value: task.area.rawValue)
                            mvDivider.frame(height: 1).padding(.horizontal, 16)
                            detailRow(icon: "clock.fill", label: "Est. Time", value: "\(task.estimatedMinutes) min")
                            if !assignedMembers.isEmpty {
                                mvDivider.frame(height: 1).padding(.horizontal, 16)
                                assignedRow(members: assignedMembers)
                            }
                            if !task.notes.isEmpty {
                                mvDivider.frame(height: 1).padding(.horizontal, 16)
                                detailRow(icon: "note.text", label: "Notes", value: task.notes)
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(mvDivider, lineWidth: 1))

                        // ── Actions ────────────────────────────────────
                        VStack(spacing: 10) {
                            let isOwner      = canWrite && vm.canDelete(task)
                            let canComplete  = vm.canMarkComplete(task)

                            // Mark Done — available to all roles
                            if canComplete {
                                Button { showMarkDoneConfirm = true } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18))
                                        Text("Mark Done").font(.system(size: 16, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                                    .background(Color(hex: "#3D7A52")!)
                                    .cornerRadius(16)
                                    .shadow(color: Color(hex: "#3D7A52")!.opacity(0.35), radius: 8, y: 4)
                                }
                                .buttonStyle(.plain)
                            }

                            // Edit + Delete — creator only
                            if isOwner {
                                HStack(spacing: 10) {
                                    Button {
                                        selectedTask = nil
                                        itemToEdit = task
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "pencil.circle.fill").font(.system(size: 16))
                                            Text("Edit Task").font(.system(size: 15, weight: .bold))
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                                        .background(mvAmber)
                                        .cornerRadius(16)
                                        .shadow(color: mvAmber.opacity(0.3), radius: 6, y: 3)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        itemToDelete = task
                                        showDeleteAlert = true
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "trash.circle.fill").font(.system(size: 16))
                                            Text("Delete").font(.system(size: 15, weight: .bold))
                                        }
                                        .foregroundColor(Color(hex: "#C0392B")!)
                                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                                        .background(Color(hex: "#C0392B")!.opacity(0.08))
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .alert("Mark as Done?", isPresented: $showMarkDoneConfirm) {
                            Button("Mark Done", role: .none) {
                                vm.markComplete(task)
                                dismiss()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will move \"\(task.title)\" to your history.")
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 40)
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(mvAmber)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(mvAmber)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(mvMuted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(mvBrown)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func assignedRow(members: [HouseholdMembership]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: members.count > 1 ? "person.2.fill" : "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(mvAmber)
                .frame(width: 22)
            Text("Assigned To")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(mvMuted)
            Spacer()
            if members.count == 1, let member = members.first {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: member.avatarHex) ?? mvAmber)
                            .frame(width: 26, height: 26)
                        Text(member.username.prefix(1).uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(member.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(mvBrown)
                        Text(member.role.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(mvMuted)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    HStack(spacing: -8) {
                        ForEach(Array(members.prefix(3)), id: \.id) { member in
                            ZStack {
                                Circle()
                                    .fill(Color(hex: member.avatarHex) ?? mvAmber)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                Text(member.username.prefix(1).uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    Text("\(members.count) members")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(mvBrown)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

#Preview { MaintenanceView() }
