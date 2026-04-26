//  HouseTask.swift
//  Homvi
//  Household task / chore model for delegation and scheduling.
//  Named HouseTask to avoid collision with Swift's concurrency Task type.

internal import SwiftUI
internal import Foundation

// MARK: - Priority Color Extension
extension HouseTask.Priority {
    var displayColor: Color {
        switch self {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

struct HouseTask: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var assignedToID: UUID?
    var dueDate: Date
    var isComplete: Bool
    var priority: Priority
    var notes: String
    var completedDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        assignedToID: UUID? = nil,
        dueDate: Date = Date(),
        isComplete: Bool = false,
        priority: Priority = .medium,
        notes: String = "",
        completedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.assignedToID = assignedToID
        self.dueDate = dueDate
        self.isComplete = isComplete
        self.priority = priority
        self.notes = notes
        self.completedDate = completedDate
    }

    var isDueToday: Bool {
        Calendar.current.isDateInToday(dueDate)
    }

    var isOverdue: Bool {
        !isComplete && dueDate < Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Priority
    enum Priority: String, Codable, CaseIterable, Identifiable {
        case low, medium, high

        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        var sortValue: Int {
            switch self { case .high: return 0; case .medium: return 1; case .low: return 2 }
        }
    }
}
