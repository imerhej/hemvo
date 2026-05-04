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
    @State private var inviteeIDs: Set<UUID> = []

    var colorHex: String { category.defaultColorHex }

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
                let members = HouseholdService.shared.household?.members ?? []
                if !members.isEmpty {
                    Section("Invitees") {
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
                                HStack {
                                    Text(member.username)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if let uuid = memberUUID, inviteeIDs.contains(uuid) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
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

