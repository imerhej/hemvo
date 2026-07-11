//  MaintenanceItem.swift
//  Hemvo
//  Home maintenance / chore item model.

internal import Foundation

// MARK: - MaintenanceItem
struct MaintenanceItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var area: HomeArea
    var frequency: Frequency
    var difficulty: Difficulty
    var lastCompleted: Date?
    var nextDue: Date
    var notes: String
    var estimatedMinutes: Int
    var assignedMemberIDs: [String]

    var createdBy: String?    // UUID string of the user who created this task

    init(
        id: UUID = UUID(),
        title: String,
        area: HomeArea = .general,
        frequency: Frequency = .monthly,
        difficulty: Difficulty = .medium,
        lastCompleted: Date? = nil,
        nextDue: Date = Date(),
        notes: String = "",
        estimatedMinutes: Int = 15,
        assignedMemberIDs: [String] = [],
        createdBy: String? = nil
    ) {
        self.id = id
        self.title = title
        self.area = area
        self.frequency = frequency
        self.difficulty = difficulty
        self.lastCompleted = lastCompleted
        self.nextDue = nextDue
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.assignedMemberIDs = assignedMemberIDs
        self.createdBy = createdBy
    }

    // Migrates old single-ID UserDefaults cache to the new array field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,     forKey: .id)
        title            = try c.decode(String.self,   forKey: .title)
        area             = try c.decode(HomeArea.self,  forKey: .area)
        frequency        = try c.decode(Frequency.self, forKey: .frequency)
        difficulty       = try c.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .medium
        lastCompleted    = try c.decodeIfPresent(Date.self,   forKey: .lastCompleted)
        nextDue          = try c.decode(Date.self,     forKey: .nextDue)
        notes            = try c.decode(String.self,   forKey: .notes)
        estimatedMinutes = try c.decode(Int.self,      forKey: .estimatedMinutes)
        createdBy        = try c.decodeIfPresent(String.self, forKey: .createdBy)
        if let ids = try c.decodeIfPresent([String].self, forKey: .assignedMemberIDs) {
            assignedMemberIDs = ids
        } else if let single = try c.decodeIfPresent(String.self, forKey: .assignedMemberID) {
            assignedMemberIDs = [single]
        } else {
            assignedMemberIDs = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                forKey: .id)
        try c.encode(title,             forKey: .title)
        try c.encode(area,              forKey: .area)
        try c.encode(frequency,         forKey: .frequency)
        try c.encode(difficulty,        forKey: .difficulty)
        try c.encodeIfPresent(lastCompleted,    forKey: .lastCompleted)
        try c.encode(nextDue,           forKey: .nextDue)
        try c.encode(notes,             forKey: .notes)
        try c.encode(estimatedMinutes,  forKey: .estimatedMinutes)
        try c.encodeIfPresent(createdBy,        forKey: .createdBy)
        try c.encode(assignedMemberIDs, forKey: .assignedMemberIDs)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, area, frequency, difficulty, lastCompleted, nextDue, notes,
             estimatedMinutes, createdBy
        case assignedMemberIDs = "assignedMemberIDs"
        case assignedMemberID  = "assignedMemberID"   // legacy decode-only key
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
        case oneTime   = "One-Time"
        case daily     = "Daily"
        case weekly    = "Weekly"
        case biweekly  = "Bi-Weekly"
        case monthly   = "Monthly"
        case quarterly = "Quarterly"
        case annually  = "Annually"

        var id: String { rawValue }

        var isRecurring: Bool { self != .oneTime }

        var days: Int {
            switch self {
            case .oneTime:   return 0
            case .daily:     return 1
            case .weekly:    return 7
            case .biweekly:  return 14
            case .monthly:   return 30
            case .quarterly: return 90
            case .annually:  return 365
            }
        }

        var intervalLabel: String {
            isRecurring ? "every \(days)d" : "no repeat"
        }

        var iconName: String {
            isRecurring ? "arrow.clockwise" : "checkmark.circle"
        }
    }

    // MARK: - Difficulty
    enum Difficulty: String, Codable, CaseIterable, Identifiable {
        case easy   = "Easy"
        case medium = "Medium"
        case hard   = "Hard"

        var id: String { rawValue }

        var colorHex: String {
            switch self {
            case .easy:   return "#4CAF74"
            case .medium: return "#C8922A"
            case .hard:   return "#E53935"
            }
        }

        var icon: String {
            switch self {
            case .easy:   return "star.fill"
            case .medium: return "star.leadinghalf.filled"
            case .hard:   return "flame.fill"
            }
        }

        var ageLabel: String {
            switch self {
            case .easy:   return "Ages 13+"
            case .medium: return "Ages 13+"
            case .hard:   return "Ages 16+"
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
