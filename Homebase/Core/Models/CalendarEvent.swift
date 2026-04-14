//  CalendarEvent.swift
//  HomeBase
//  Family calendar event model.

internal import Foundation

// MARK: - CalendarEvent
struct CalendarEvent: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var date: Date
    var endDate: Date?
    var assignedToID: UUID?
    var isAllDay: Bool
    var notes: String
    var category: EventCategory
    var colorHex: String

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        endDate: Date? = nil,
        assignedToID: UUID? = nil,
        isAllDay: Bool = false,
        notes: String = "",
        category: EventCategory = .general,
        colorHex: String = "#4CAF74"
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.endDate = endDate
        self.assignedToID = assignedToID
        self.isAllDay = isAllDay
        self.notes = notes
        self.category = category
        self.colorHex = colorHex
    }

    var isUpcoming: Bool { date >= Date() }

    var formattedTime: String {
        if isAllDay { return "All day" }
        return date.formatted(.dateTime.hour().minute())
    }

    var formattedDate: String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - EventCategory
    enum EventCategory: String, Codable, CaseIterable, Identifiable {
        case general    = "General"
        case medical    = "Medical"
        case school     = "School"
        case work       = "Work"
        case family     = "Family"
        case social     = "Social"
        case errand     = "Errand"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .general:  return "calendar"
            case .medical:  return "cross.case.fill"
            case .school:   return "backpack.fill"
            case .work:     return "briefcase.fill"
            case .family:   return "house.fill"
            case .social:   return "person.2.fill"
            case .errand:   return "bag.fill"
            }
        }

        var defaultColorHex: String {
            switch self {
            case .general:  return "#4CAF74"
            case .medical:  return "#F44336"
            case .school:   return "#2196F3"
            case .work:     return "#FF9800"
            case .family:   return "#9C27B0"
            case .social:   return "#00BCD4"
            case .errand:   return "#795548"
            }
        }
    }
}
