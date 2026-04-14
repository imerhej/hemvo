//  AddEventView.swift + TaskDelegationView.swift
//  HomeBase

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

    @State private var title      = ""
    @State private var date       = Date()
    @State private var isAllDay   = false
    @State private var notes      = ""
    @State private var category   = CalendarEvent.EventCategory.general
    @State private var assignedTo: UUID? = nil

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
                if !vm.householdMembers.isEmpty {
                    Section("Assign To") {
                        Picker("Member", selection: $assignedTo) {
                            Text("No one").tag(nil as UUID?)
                            ForEach(vm.householdMembers) { m in
                                Text(m.name).tag(m.id as UUID?)
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
                            category: category, colorHex: colorHex
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

