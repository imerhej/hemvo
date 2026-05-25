//  AddEventView.swift + TaskDelegationView.swift
//  Hemvo

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

// MARK: - AddEventView
struct AddEventView: View {
    @ObservedObject var vm: ScheduleViewModel
    @Environment(\.dismiss) var dismiss
    var preselectedDate: Date = Date()

    @State private var title       = ""
    @State private var date        = Date()
    @State private var isAllDay    = false
    @State private var notes       = ""
    @State private var category    = CalendarEvent.EventCategory.general
    @State private var assignedTo: UUID? = nil
    @State private var repeatRule  = CalendarEvent.RecurrenceRule.never
    @State private var alertOption = "None"
    @State private var inviteeIDs: Set<UUID> = []

    private let alertOptions = ["None", "5 minutes before", "15 minutes before",
                                "30 minutes before", "1 hour before", "1 day before"]

    var colorHex: String { category.defaultColorHex }

    private var members: [HouseholdMembership] {
        HouseholdService.shared.household?.members ?? []
    }

    private var inviteeSummary: String {
        if inviteeIDs.isEmpty { return "None" }
        let names = members
            .filter { inviteeIDs.contains(UUID(uuidString: $0.id) ?? UUID()) }
            .map(\.username)
        return names.count <= 2 ? names.joined(separator: ", ") : "\(names.count) selected"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Details") {
                    TextField("Title (e.g. Dentist Appointment)", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(CalendarEvent.EventCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                        }
                    }
                }
                Section("Time") {
                    Toggle("All Day", isOn: $isAllDay)
                    DatePicker(
                        isAllDay ? "Date" : "Date & Time",
                        selection: $date,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                }
                Section("Repeat") {
                    Picker("Repeat", selection: $repeatRule) {
                        ForEach(CalendarEvent.RecurrenceRule.allCases, id: \.self) { rule in
                            Text(rule.rawValue).tag(rule)
                        }
                    }
                }
                if !isAllDay {
                    Section("Alert") {
                        Picker("Alert", selection: $alertOption) {
                            ForEach(alertOptions, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                if !members.isEmpty {
                    Section("Invitees") {
                        Menu {
                            ForEach(members) { member in
                                let memberUUID = UUID(uuidString: member.id)
                                Button {
                                    guard let uuid = memberUUID else { return }
                                    if inviteeIDs.contains(uuid) {
                                        inviteeIDs.remove(uuid)
                                    } else {
                                        inviteeIDs.insert(uuid)
                                    }
                                } label: {
                                    if let uuid = memberUUID, inviteeIDs.contains(uuid) {
                                        Label(member.username, systemImage: "checkmark")
                                    } else {
                                        Text(member.username)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Invitees")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(inviteeSummary)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(.secondary)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                if !members.isEmpty {
                    Section("Assign To") {
                        Picker("Member", selection: $assignedTo) {
                            Text("No one").tag(nil as UUID?)
                            ForEach(members) { m in
                                Text(m.username).tag(UUID(uuidString: m.id) as UUID?)
                            }
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Add Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.addEvent(CalendarEvent(
                            title: title, date: date, assignedToID: assignedTo,
                            isAllDay: isAllDay, notes: notes,
                            category: category, colorHex: colorHex,
                            repeatRule: repeatRule,
                            alertOption: isAllDay ? "None" : alertOption,
                            inviteeIDs: Array(inviteeIDs)
                        ))
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .onAppear { date = preselectedDate }
        }
    }
}

