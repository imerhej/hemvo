//  MaintenanceItem.swift
//  Homvi
//  Home maintenance / chore item model.

internal import Foundation

// MARK: - MaintenanceItem
struct MaintenanceItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var area: HomeArea
    var frequency: Frequency
    var lastCompleted: Date?
    var nextDue: Date
    var notes: String
    var estimatedMinutes: Int
    var assignedMemberID: String?

    init(
        id: UUID = UUID(),
        title: String,
        area: HomeArea = .general,
        frequency: Frequency = .monthly,
        lastCompleted: Date? = nil,
        nextDue: Date = Date(),
        notes: String = "",
        estimatedMinutes: Int = 15,
        assignedMemberID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.area = area
        self.frequency = frequency
        self.lastCompleted = lastCompleted
        self.nextDue = nextDue
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.assignedMemberID = assignedMemberID
    }

    var daysUntilDue: Int {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due   = cal.startOfDay(for: nextDue)
        return cal.dateComponents([.day], from: today, to: due).day ?? 0
    }

    var isOverdue: Bool  { Calendar.current.startOfDay(for: nextDue) < Calendar.current.startOfDay(for: Date()) }
    var isDueSoon: Bool  { !isOverdue && daysUntilDue <= 7 }
    var isUpToDate: Bool { !isOverdue && !isDueSoon }

    var statusLabel: String {
        if isOverdue  { return "Overdue by \(abs(daysUntilDue))d" }
        if daysUntilDue == 0 { return "Due today" }
        return "Due in \(daysUntilDue)d"
    }

    mutating func markComplete() {
        lastCompleted = Date()
        nextDue = Calendar.current.date(byAdding: .day, value: frequency.days, to: Date()) ?? Date()
    }

    // MARK: - HomeArea
    enum HomeArea: String, Codable, CaseIterable, Identifiable {
        case kitchen  = "Kitchen"
        case bathroom = "Bathroom"
        case bedroom  = "Bedroom"
        case garage   = "Garage"
        case yard     = "Yard"
        case hvac     = "HVAC"
        case general  = "General"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .kitchen:  return "fork.knife"
            case .bathroom: return "shower.fill"
            case .bedroom:  return "bed.double.fill"
            case .garage:   return "car.fill"
            case .yard:     return "leaf.fill"
            case .hvac:     return "wind"
            case .general:  return "house.fill"
            }
        }
    }

    // MARK: - Frequency
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily     = "Daily"
        case weekly    = "Weekly"
        case biweekly  = "Bi-Weekly"
        case monthly   = "Monthly"
        case quarterly = "Quarterly"
        case annually  = "Annually"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .daily:     return 1
            case .weekly:    return 7
            case .biweekly:  return 14
            case .monthly:   return 30
            case .quarterly: return 90
            case .annually:  return 365
            }
        }
    }
}

// MARK: - SeasonalTask
struct SeasonalTask: Identifiable, Equatable {
    let id: UUID
    let title: String
    let description: String
    var isComplete: Bool

    init(id: UUID = UUID(), title: String, description: String, isComplete: Bool = false) {
        self.id = id; self.title = title
        self.description = description; self.isComplete = isComplete
    }
}

// MARK: - Season
enum Season: String, CaseIterable, Identifiable {
    case spring = "Spring"
    case summer = "Summer"
    case fall   = "Fall"
    case winter = "Winter"

    var id: String { rawValue }

    var emoji: String {
        switch self { case .spring: return "🌸"; case .summer: return "☀️"
                      case .fall:   return "🍂"; case .winter: return "❄️" }
    }

    static var current: Season {
        switch Calendar.current.component(.month, from: Date()) {
        case 3...5:  return .spring
        case 6...8:  return .summer
        case 9...11: return .fall
        default:     return .winter
        }
    }

    var tasks: [SeasonalTask] {
        switch self {
        case .spring: return [
            SeasonalTask(title: "Test smoke detectors",        description: "Replace batteries if needed"),
            SeasonalTask(title: "Clean gutters",               description: "Remove winter debris & check for damage"),
            SeasonalTask(title: "Service AC unit",             description: "Change filter and check refrigerant"),
            SeasonalTask(title: "Inspect roof",                description: "Look for winter damage or missing shingles"),
            SeasonalTask(title: "Deep clean kitchen",          description: "Clean coils, oven, and behind appliances"),
            SeasonalTask(title: "Check window & door seals",   description: "Replace weatherstripping as needed"),
        ]
        case .summer: return [
            SeasonalTask(title: "Check window seals",          description: "Keep cool air in, hot air out"),
            SeasonalTask(title: "Clean dryer vent",            description: "Fire hazard if clogged"),
            SeasonalTask(title: "Trim trees & bushes",         description: "Keep branches away from house"),
            SeasonalTask(title: "Test garage door safety",     description: "Lubricate tracks and test auto-reverse"),
            SeasonalTask(title: "Inspect deck or patio",       description: "Check for rot, loose boards, or splinters"),
        ]
        case .fall: return [
            SeasonalTask(title: "Flush water heater",          description: "Remove sediment buildup annually"),
            SeasonalTask(title: "Inspect fireplace & chimney", description: "Schedule a sweep before first use"),
            SeasonalTask(title: "Winterize sprinklers",        description: "Blow out lines to prevent freezing"),
            SeasonalTask(title: "Service furnace/heating",     description: "Replace filter, test thermostat"),
            SeasonalTask(title: "Stock emergency supplies",    description: "Flashlights, batteries, non-perishable food"),
            SeasonalTask(title: "Clean refrigerator coils",    description: "Improves efficiency by up to 30%"),
        ]
        case .winter: return [
            SeasonalTask(title: "Check pipes for freezing",    description: "Insulate exposed pipes in unheated spaces"),
            SeasonalTask(title: "Test CO detectors",           description: "Carbon monoxide risk rises in winter"),
            SeasonalTask(title: "Inspect weatherstripping",    description: "Check all exterior doors and windows"),
            SeasonalTask(title: "Review home insurance",       description: "Annual policy review and update"),
            SeasonalTask(title: "Clean humidifier",            description: "Prevent mold and bacteria buildup"),
        ]
        }
    }
}
