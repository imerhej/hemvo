//  User.swift
//  Homvi
//  User profile and household member models.

internal import Foundation

// MARK: - User
struct User: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var username: String
    var email: String
    var householdMembers: [HouseholdMember]
    var subscriptionStatus: SubscriptionStatus
    var trialStartDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        username: String,
        email: String,
        householdMembers: [HouseholdMember] = [],
        subscriptionStatus: SubscriptionStatus = .trial,
        trialStartDate: Date? = Date()
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.email = email
        self.householdMembers = householdMembers
        self.subscriptionStatus = subscriptionStatus
        self.trialStartDate = trialStartDate
    }

    // Backward-compatible decode: existing stored users without username fall back to email prefix
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decode(UUID.self, forKey: .id)
        name               = try c.decode(String.self, forKey: .name)
        email              = try c.decode(String.self, forKey: .email)
        username           = try c.decodeIfPresent(String.self, forKey: .username)
                             ?? email.components(separatedBy: "@").first ?? email
        householdMembers   = try c.decodeIfPresent([HouseholdMember].self, forKey: .householdMembers) ?? []
        subscriptionStatus = try c.decodeIfPresent(SubscriptionStatus.self, forKey: .subscriptionStatus) ?? .trial
        trialStartDate     = try c.decodeIfPresent(Date.self, forKey: .trialStartDate)
    }

    enum SubscriptionStatus: String, Codable {
        case trial, active, expired, none
    }

    var initials: String {
        name.components(separatedBy: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0) }
            .joined()
            .uppercased()
    }

    var firstName: String {
        name.components(separatedBy: " ").first ?? name
    }
}

// MARK: - HouseholdMember
struct HouseholdMember: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var role: String
    var avatarColorHex: String

    init(
        id: UUID = UUID(),
        name: String,
        role: String,
        avatarColorHex: String = "#4CAF74"
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.avatarColorHex = avatarColorHex
    }

    var initials: String {
        name.components(separatedBy: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0) }
            .joined()
            .uppercased()
    }

    static let sampleColors = [
        "#4CAF74", "#2196F3", "#FF9800",
        "#E91E63", "#9C27B0", "#00BCD4"
    ]
}
