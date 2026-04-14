//  User.swift
//  HomeBase
//  User profile and household member models.

internal import Foundation

// MARK: - User
struct User: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var email: String
    var householdMembers: [HouseholdMember]
    var subscriptionStatus: SubscriptionStatus
    var trialStartDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        email: String,
        householdMembers: [HouseholdMember] = [],
        subscriptionStatus: SubscriptionStatus = .trial,
        trialStartDate: Date? = Date()
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.householdMembers = householdMembers
        self.subscriptionStatus = subscriptionStatus
        self.trialStartDate = trialStartDate
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
