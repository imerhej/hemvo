//  CalendarEvent.swift
//  Hemvo
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
    var repeatRule: RecurrenceRule
    var travelTime: String
    var alertOption: String
    var createdBy: String?
    var inviteeIDs: [UUID]
    var scope: EventScope

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        endDate: Date? = nil,
        assignedToID: UUID? = nil,
        isAllDay: Bool = false,
        notes: String = "",
        category: EventCategory = .general,
        colorHex: String = "#4CAF74",
        repeatRule: RecurrenceRule = .never,
        travelTime: String = "None",
        alertOption: String = "None",
        createdBy: String? = nil,
        inviteeIDs: [UUID] = [],
        scope: EventScope = .personal
    ) {
        self.id           = id
        self.title        = title
        self.date         = date
        self.endDate      = endDate
        self.assignedToID = assignedToID
        self.isAllDay     = isAllDay
        self.notes        = notes
        self.category     = category
        self.colorHex     = colorHex
        self.repeatRule   = repeatRule
        self.travelTime   = travelTime
        self.alertOption  = alertOption
        self.createdBy    = createdBy
        self.inviteeIDs   = inviteeIDs
        self.scope        = scope
    }

    // Backward-compatible decode: old events stored before `scope` was added decode as .personal
    init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self, forKey: .id)
        title          = try c.decode(String.self, forKey: .title)
        date           = try c.decode(Date.self, forKey: .date)
        endDate        = try c.decodeIfPresent(Date.self, forKey: .endDate)
        assignedToID   = try c.decodeIfPresent(UUID.self, forKey: .assignedToID)
        isAllDay       = try c.decode(Bool.self, forKey: .isAllDay)
        notes          = try c.decode(String.self, forKey: .notes)
        category       = try c.decode(EventCategory.self, forKey: .category)
        colorHex       = try c.decode(String.self, forKey: .colorHex)
        repeatRule     = try c.decode(RecurrenceRule.self, forKey: .repeatRule)
        travelTime     = try c.decode(String.self, forKey: .travelTime)
        alertOption    = try c.decode(String.self, forKey: .alertOption)
        createdBy      = try c.decodeIfPresent(String.self, forKey: .createdBy)
        inviteeIDs     = (try? c.decode([UUID].self, forKey: .inviteeIDs)) ?? []
        scope          = (try? c.decode(EventScope.self, forKey: .scope)) ?? .personal
    }

    var isUpcoming: Bool { date >= Date() }

    func occursOn(date: Date) -> Bool {
        guard repeatRule != .never else { return false }
        let cal = Calendar.current
        let startDay  = cal.startOfDay(for: self.date)
        let targetDay = cal.startOfDay(for: date)
        guard targetDay > startDay else { return false }
        switch repeatRule {
        case .never:    return false
        case .daily:    return true
        case .weekly:
            return cal.component(.weekday, from: date) == cal.component(.weekday, from: self.date)
        case .biweekly:
            let days = cal.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
            return days % 14 == 0
        case .monthly:
            return cal.component(.day, from: date) == cal.component(.day, from: self.date)
        case .yearly:
            let src = cal.dateComponents([.month, .day], from: self.date)
            let tgt = cal.dateComponents([.month, .day], from: date)
            return src.month == tgt.month && src.day == tgt.day
        }
    }

    // MARK: - EventScope
    enum EventScope: String, Codable, CaseIterable {
        case personal  = "Personal"
        case household = "Household"

        var iconName: String {
            switch self {
            case .personal:  return "person.fill"
            case .household: return "house.fill"
            }
        }
    }

    // MARK: - RecurrenceRule
    enum RecurrenceRule: String, Codable, CaseIterable {
        case never    = "Never"
        case daily    = "Every Day"
        case weekly   = "Every Week"
        case biweekly = "Every 2 Weeks"
        case monthly  = "Every Month"
        case yearly   = "Every Year"
    }

    var formattedTime: String {
        if isAllDay { return "All day" }
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits))
    }

    var formattedDate: String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - EventCategory
    enum EventCategory: String, Codable, CaseIterable, Identifiable {
        case general = "General"
        case medical = "Medical"
        case school  = "School"
        case work    = "Work"
        case family  = "Family"
        case social  = "Social"
        case errand  = "Errand"
        case sports  = "Sports"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .general: return "calendar"
            case .medical: return "cross.case.fill"
            case .school:  return "backpack.fill"
            case .work:    return "briefcase.fill"
            case .family:  return "birthday.cake.fill"
            case .social:  return "person.2.fill"
            case .errand:  return "cart.fill"
            case .sports:  return "soccerball"
            }
        }

        var defaultColorHex: String {
            switch self {
            case .general: return "#4CAF74"
            case .medical: return "#F44336"
            case .school:  return "#2196F3"
            case .work:    return "#FF9800"
            case .family:  return "#9C27B0"
            case .social:  return "#00BCD4"
            case .errand:  return "#795548"
            case .sports:  return "#E53935"
            }
        }
    }
}
