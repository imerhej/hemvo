
//  AddMaintenanceTaskSheet.swift
//  Hemvo
//  New/Edit task sheet. Matches screenshot:
//  quick templates row, task name field, home area icon grid,
//  frequency list with amber selected row.

internal import SwiftUI

struct AddMaintenanceTaskSheet: View {

    @ObservedObject var vm: MaintenanceViewModel
    var editing: MaintenanceItem? = nil
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var householdService = HouseholdService.shared

    @State private var title:            String                       = ""
    @State private var area:             MaintenanceItem.HomeArea    = .general
    @State private var frequency:        MaintenanceItem.Frequency   = .monthly
    @State private var estimatedMinutes: Int                         = 30
    @State private var notes:            String                      = ""
    @State private var nextDueDate:      Date                        = Date()
    @State private var assignedMemberIDs: [String]                   = []
    @State private var showDatePicker:   Bool                        = false
    @State private var showChoreLibrary: Bool                        = false
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    private var isEditing: Bool { editing != nil }
    private var isValid:   Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private var youngestAssignedRole: HouseholdRole? {
        guard let members = householdService.household?.members,
              !assignedMemberIDs.isEmpty else { return nil }
        let roles = assignedMemberIDs.compactMap { id in members.first(where: { $0.id == id })?.role }
        if roles.contains(.teen) { return .teen }
        return nil
    }

    private var libraryMaxDifficulty: MaintenanceItem.Difficulty {
        switch youngestAssignedRole {
        case .teen:  return .medium
        default:     return .hard
        }
    }

    private let amber   = Color(hex: "#C8922A")!
    private let amberBg = Color(hex: "#F5E4C3")!
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let divider = Color(hex: "#E6DDD0")!
    private let cream   = Color(hex: "#F5F0E8")!

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        // ── Home Area ──────────────────────────────────
                        VStack(alignment: .leading, spacing: 14) {
                            sectionLabel(icon: "house.fill", text: "HOME AREA")
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                                spacing: 14
                            ) {
                                ForEach(MaintenanceItem.HomeArea.allCases) { a in
                                    let isSel = area == a
                                    Button { withAnimation(.spring(response: 0.25)) { area = a } } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(isSel ? amber : Color(hex: "#EFEFEF")!)
                                                    .frame(width: 60, height: 60)
                                                Image(systemName: a.iconName)
                                                    .font(.system(size: 22, weight: .semibold))
                                                    .foregroundColor(isSel ? .white : brown)
                                            }
                                            .scaleEffect(isSel ? 1.06 : 1.0)
                                            .animation(.spring(response: 0.25), value: isSel)

                                            Text(a.rawValue)
                                                .font(.system(size: 11, weight: isSel ? .heavy : .medium))
                                                .foregroundColor(isSel ? amber : muted)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(divider, lineWidth: 1))

                        // ── Task Name ──────────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel(icon: "tag.fill", text: "TASK NAME")
                            TextField("e.g. Replace HVAC Filter", text: $title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(brown)
                                .focused($titleFocused)
                                .submitLabel(.next)
                                .onSubmit { notesFocused = true }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .stroke(titleFocused ? amber.opacity(0.6) : divider,
                                    lineWidth: titleFocused ? 2 : 1))
                        .animation(.easeInOut(duration: 0.15), value: titleFocused)

                        // ── Frequency ──────────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel(icon: "arrow.clockwise", text: "FREQUENCY")
                            VStack(spacing: 0) {
                                ForEach(Array(MaintenanceItem.Frequency.allCases.enumerated()),
                                        id: \.element) { idx, freq in
                                    let isSel = frequency == freq
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) { frequency = freq }
                                    } label: {
                                        HStack {
                                            Text(freq.rawValue)
                                                .font(.system(size: 15, weight: isSel ? .bold : .regular))
                                                .foregroundColor(isSel ? amber : brown)
                                            Spacer()
                                            Text("every \(freq.days)d")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(isSel ? amber : muted)
                                            if isSel {
                                                ZStack {
                                                    Circle().fill(amber).frame(width: 22, height: 22)
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .black))
                                                        .foregroundColor(.white)
                                                }
                                                .padding(.leading, 8)
                                            }
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 14)
                                        .background(isSel ? amberBg : Color.white)
                                        .animation(.easeInOut(duration: 0.15), value: isSel)
                                    }
                                    .buttonStyle(.plain)

                                    if idx < MaintenanceItem.Frequency.allCases.count - 1 {
                                        divider.frame(height: 1).padding(.horizontal, 16)
                                    }
                                }
                            }
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(divider, lineWidth: 1))
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(divider, lineWidth: 1))

                        // ── Est. Time ──────────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel(icon: "clock.fill", text: "ESTIMATED TIME")
                            HStack {
                                Text("\(estimatedMinutes) min")
                                    .font(.system(size: 16, weight: .bold)).foregroundColor(brown)
                                Spacer()
                                HStack(spacing: 0) {
                                    Button {
                                        if estimatedMinutes > 5 { estimatedMinutes -= 5 }
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.system(size: 14, weight: .bold)).foregroundColor(amber)
                                            .frame(width: 38, height: 38)
                                            .background(amberBg).cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)

                                    Text("\(estimatedMinutes)")
                                        .font(.system(size: 15, weight: .bold)).foregroundColor(brown)
                                        .frame(width: 44)

                                    Button {
                                        estimatedMinutes += 5
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .bold)).foregroundColor(amber)
                                            .frame(width: 38, height: 38)
                                            .background(amberBg).cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(divider, lineWidth: 1))

                        // ── Next Due Date ──────────────────────────────
                        Button { showDatePicker = true } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel(icon: "calendar", text: "NEXT DUE DATE")
                                HStack {
                                    Text("Due on")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(brown)
                                    Spacer()
                                    Text(nextDueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(amber)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(muted.opacity(0.5))
                                }
                            }
                            .padding(16)
                            .background(Color.white)
                            .cornerRadius(18)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(divider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        // ── Assigned To ────────────────────────────────
                        if let members = householdService.household?.members, !members.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    sectionLabel(icon: "person.2.fill", text: "ASSIGNED TO")
                                    Spacer()
                                    if !assignedMemberIDs.isEmpty {
                                        Text("\(assignedMemberIDs.count) selected")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(amber)
                                    }
                                }
                                VStack(spacing: 0) {
                                    let unassignedSel = assignedMemberIDs.isEmpty
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) { assignedMemberIDs = [] }
                                    } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(unassignedSel ? amber : Color(hex: "#EFEFEF")!)
                                                    .frame(width: 36, height: 36)
                                                Image(systemName: "person.slash.fill")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(unassignedSel ? .white : muted)
                                            }
                                            Text("Unassigned")
                                                .font(.system(size: 15, weight: unassignedSel ? .bold : .regular))
                                                .foregroundColor(unassignedSel ? amber : brown)
                                            Spacer()
                                            if unassignedSel {
                                                ZStack {
                                                    Circle().fill(amber).frame(width: 22, height: 22)
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .black))
                                                        .foregroundColor(.white)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 12)
                                        .background(unassignedSel ? amberBg : Color.white)
                                        .animation(.easeInOut(duration: 0.15), value: unassignedSel)
                                    }
                                    .buttonStyle(.plain)

                                    ForEach(Array(members.enumerated()), id: \.element.id) { _, member in
                                        let isSel = assignedMemberIDs.contains(member.id)
                                        divider.frame(height: 1).padding(.horizontal, 16)
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                if isSel {
                                                    assignedMemberIDs.removeAll { $0 == member.id }
                                                } else {
                                                    assignedMemberIDs.append(member.id)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 12) {
                                                ZStack {
                                                    Circle()
                                                        .fill(isSel ? amber : (Color(hex: member.avatarHex) ?? Color(hex: "#EFEFEF")!))
                                                        .frame(width: 36, height: 36)
                                                    Text(member.username.prefix(1).uppercased())
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundColor(.white)
                                                }
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(member.username)
                                                        .font(.system(size: 15, weight: isSel ? .bold : .regular))
                                                        .foregroundColor(isSel ? amber : brown)
                                                    Text(member.role.rawValue)
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundColor(muted)
                                                }
                                                Spacer()
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(isSel ? amber : Color(hex: "#EFEFEF")!)
                                                        .frame(width: 22, height: 22)
                                                    if isSel {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 10, weight: .black))
                                                            .foregroundColor(.white)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            .background(isSel ? amberBg : Color.white)
                                            .animation(.easeInOut(duration: 0.15), value: isSel)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(divider, lineWidth: 1))
                            }
                            .padding(16)
                            .background(Color.white)
                            .cornerRadius(18)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(divider, lineWidth: 1))
                        }

                        // ── Suggested Chores Banner ────────────────────
                        if youngestAssignedRole != nil {
                            Button { showChoreLibrary = true } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(amber.opacity(0.12))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(amber)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Suggested Chores")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(brown)
                                        Text("Browse tasks suitable for teens and up")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(muted.opacity(0.5))
                                }
                                .padding(16)
                                .background(Color.white)
                                .cornerRadius(18)
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(amber.opacity(0.35), lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // ── Notes ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel(icon: "note.text", text: "NOTES (OPTIONAL)")
                            TextField("Any details or reminders…", text: $notes, axis: .vertical)
                                .lineLimit(3...5)
                                .font(.system(size: 14)).foregroundColor(brown)
                                .focused($notesFocused)
                                .submitLabel(.done)
                                .onSubmit { notesFocused = false }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(divider, lineWidth: 1))

                        // ── Save button ────────────────────────────────
                        Button { save() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isEditing ? "checkmark.circle.fill" : "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text(isEditing ? "Save Changes" : "Add Task")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(isValid ? amber : Color(hex: "#C5C0B8")!)
                            .cornerRadius(16)
                            .shadow(color: isValid ? amber.opacity(0.4) : .clear, radius: 10, y: 4)
                            .animation(.easeInOut(duration: 0.15), value: isValid)
                        }
                        .disabled(!isValid)
                    }
                    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 40)
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(amber)
                }
            }
            .sheet(isPresented: $showChoreLibrary) {
                ChoreLibrarySheet(maxDifficulty: libraryMaxDifficulty) { template in
                    applyTemplate(template)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    DatePicker("", selection: $nextDueDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(amber)
                        .labelsHidden()
                        .padding(.horizontal)
                        .navigationTitle("Select Date")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showDatePicker = false }
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(amber)
                            }
                        }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                if let item = editing {
                    title             = item.title
                    area              = item.area
                    frequency         = item.frequency
                    estimatedMinutes  = item.estimatedMinutes
                    notes             = item.notes
                    nextDueDate       = item.nextDue
                    assignedMemberIDs = item.assignedMemberIDs
                } else {
                    nextDueDate = Calendar.current.date(byAdding: .day, value: frequency.days, to: Date()) ?? Date()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { titleFocused = true }
                }
            }
            .onChange(of: frequency) { _, newFreq in
                if !isEditing {
                    nextDueDate = Calendar.current.date(byAdding: .day, value: newFreq.days, to: Date()) ?? Date()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers
    private func save() {
        if isEditing, var updated = editing {
            updated.title             = title.trimmingCharacters(in: .whitespaces)
            updated.area              = area
            updated.frequency         = frequency
            updated.estimatedMinutes  = estimatedMinutes
            updated.notes             = notes
            updated.nextDue           = nextDueDate
            updated.assignedMemberIDs = assignedMemberIDs
            vm.updateItem(updated)
        } else {
            let item = MaintenanceItem(
                title:             title.trimmingCharacters(in: .whitespaces),
                area:              area,
                frequency:         frequency,
                nextDue:           nextDueDate,
                notes:             notes,
                estimatedMinutes:  estimatedMinutes,
                assignedMemberIDs: assignedMemberIDs
            )
            vm.addItem(item)
        }
        dismiss()
    }

    private func applyTemplate(_ template: ChoreTemplate) {
        withAnimation(.easeInOut(duration: 0.2)) {
            title            = template.title
            area             = template.area
            frequency        = template.frequency
            estimatedMinutes = template.estimatedMinutes
            nextDueDate      = Calendar.current.date(byAdding: .day, value: template.frequency.days, to: Date()) ?? Date()
        }
    }

    private func sectionLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold)).foregroundColor(muted)
            Text(text)
                .font(.system(size: 10, weight: .heavy)).kerning(1.3).foregroundColor(muted)
        }
    }
}

#Preview {
    AddMaintenanceTaskSheet(vm: MaintenanceViewModel())
}
