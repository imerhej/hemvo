//  AddChoreView.swift
//  Hemvo
//  Form to add or edit a home maintenance chore.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

struct AddChoreView: View {

    @ObservedObject var vm: MaintenanceViewModel
    @Environment(\.dismiss) var dismiss

    var editingItem: MaintenanceItem? = nil

    @State private var title             = ""
    @State private var area              = MaintenanceItem.HomeArea.general
    @State private var frequency         = MaintenanceItem.Frequency.monthly
    @State private var nextDue           = Date()
    @State private var estimatedMinutes  = 15
    @State private var notes             = ""

    var isEditing: Bool { editingItem != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chore Details") {
                    TextField("Title (e.g. Replace HVAC Filter)", text: $title)

                    Picker("Home Area", selection: $area) {
                        ForEach(MaintenanceItem.HomeArea.allCases) { a in
                            Label(a.rawValue, systemImage: a.iconName).tag(a)
                        }
                    }

                    Picker("Frequency", selection: $frequency) {
                        ForEach(MaintenanceItem.Frequency.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                }

                Section("Schedule") {
                    DatePicker("Next Due Date", selection: $nextDue, displayedComponents: .date)
                    Stepper(
                        "Estimated Time: \(estimatedMinutes) min",
                        value: $estimatedMinutes,
                        in: 5...480,
                        step: 5
                    )
                }

                Section("Notes") {
                    TextField("Optional notes or instructions…", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                // Quick-fill templates
                if !isEditing {
                    Section("Quick Templates") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ChoreTemplate.all) { template in
                                    Button {
                                        title            = template.title
                                        area             = template.area
                                        frequency        = template.frequency
                                        estimatedMinutes = template.estimatedMinutes
                                        nextDue          = Date.daysFromNow(template.frequency.days)
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: template.icon ?? template.difficulty.icon)
                                                .font(.title3)
                                                .foregroundColor(.homeBaseGreen)
                                            Text(template.title)
                                                .font(.caption)
                                                .multilineTextAlignment(.center)
                                                .foregroundColor(.primary)
                                        }
                                        .padding(10)
                                        .frame(width: 90)
                                        .background(Color(.systemBackground))
                                        .cornerRadius(10)
                                        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Chore" : "Add Chore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.isEmpty)
                }
            }
            .onAppear { prefill() }
        }
    }

    // MARK: - Prefill for editing
    private func prefill() {
        guard let item = editingItem else { return }
        title            = item.title
        area             = item.area
        frequency        = item.frequency
        nextDue          = item.nextDue
        estimatedMinutes = item.estimatedMinutes
        notes            = item.notes
    }

    // MARK: - Save
    private func save() {
        let item = MaintenanceItem(
            id:                editingItem?.id ?? UUID(),
            title:             title,
            area:              area,
            frequency:         frequency,
            lastCompleted:     editingItem?.lastCompleted,
            nextDue:           nextDue,
            notes:             notes,
            estimatedMinutes:  estimatedMinutes
        )
        if isEditing {
            vm.updateItem(item)
        } else {
            vm.addItem(item)
        }
        dismiss()
    }
}

// MARK: - ChoreTemplate
struct ChoreTemplate: Identifiable {
    let id: String
    let title: String
    let area: MaintenanceItem.HomeArea
    let frequency: MaintenanceItem.Frequency
    let difficulty: MaintenanceItem.Difficulty
    let estimatedMinutes: Int
    let icon: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        area: MaintenanceItem.HomeArea,
        frequency: MaintenanceItem.Frequency,
        difficulty: MaintenanceItem.Difficulty = .hard,
        estimatedMinutes: Int,
        icon: String? = nil
    ) {
        self.id = id; self.title = title; self.area = area
        self.frequency = frequency; self.difficulty = difficulty
        self.estimatedMinutes = estimatedMinutes; self.icon = icon
    }

    static let all: [ChoreTemplate] = [
        ChoreTemplate(title: "HVAC Filter",    area: .hvac,     frequency: .monthly,   difficulty: .hard,   estimatedMinutes: 10,  icon: "wind"),
        ChoreTemplate(title: "Clean Gutters",  area: .yard,     frequency: .quarterly, difficulty: .hard,   estimatedMinutes: 60,  icon: "leaf.fill"),
        ChoreTemplate(title: "Test Alarms",    area: .general,  frequency: .monthly,   difficulty: .medium, estimatedMinutes: 10,  icon: "bell.fill"),
        ChoreTemplate(title: "Deep Kitchen",   area: .kitchen,  frequency: .quarterly, difficulty: .hard,   estimatedMinutes: 90,  icon: "fork.knife"),
        ChoreTemplate(title: "Flush Heater",   area: .general,  frequency: .annually,  difficulty: .hard,   estimatedMinutes: 45,  icon: "flame.fill"),
        ChoreTemplate(title: "Inspect Roof",   area: .general,  frequency: .annually,  difficulty: .hard,   estimatedMinutes: 30,  icon: "house.fill"),
    ]
}

#Preview {
    AddChoreView(vm: MaintenanceViewModel())
}
