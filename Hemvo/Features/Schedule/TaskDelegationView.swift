//  TaskDelegationView.swift
//  Hemvo

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications


// MARK: - TaskDelegationView
struct TaskDelegationView: View {
    @ObservedObject var vm: ScheduleViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title      = ""
    @State private var dueDate    = Date()
    @State private var priority   = HouseTask.Priority.medium
    @State private var notes      = ""
    @State private var assignedTo: UUID? = nil

    private enum Field { case title, notes }
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Task title (e.g. Clean garage)", text: $title)
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focus = .notes }
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                    Picker("Priority", selection: $priority) {
                        ForEach(HouseTask.Priority.allCases) { p in
                            Label(p.label, systemImage: "flag.fill").foregroundColor(p.displayColor).tag(p)
                        }
                    }
                }
                if !vm.householdMembers.isEmpty {
                    Section("Assign To") {
                        Picker("Member", selection: $assignedTo) {
                            Text("Anyone").tag(nil as UUID?)
                            ForEach(vm.householdMembers) { m in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: m.avatarColorHex) ?? .homeBaseGreen)
                                        .frame(width: 10, height: 10)
                                    Text(m.name)
                                }
                                .tag(m.id as UUID?)
                            }
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focus, equals: .notes)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                }

                // Existing tasks
                if !vm.tasks.isEmpty {
                    Section("All Tasks") {
                        ForEach(vm.tasks) { task in
                            TaskDetailRow(
                                task: task,
                                member: vm.member(for: task.assignedToID),
                                onToggle: { vm.toggleTask(task) },
                                onDelete: { vm.deleteTask(task) }
                            )
                        }
                        .onDelete { vm.deleteTasks(at: $0) }
                    }
                }
            }
            .navigationTitle("Delegate Task")
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focus = .title }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        vm.addTask(HouseTask(
                            title: title, assignedToID: assignedTo,
                            dueDate: dueDate, priority: priority, notes: notes
                        ))
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}
