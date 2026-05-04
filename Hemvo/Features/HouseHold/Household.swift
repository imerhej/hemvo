internal import Foundation

// MARK: - Household

/// The shared data namespace every member reads and writes to.
/// Stored in UserDefaults keyed by householdID; synced via CloudKit.
struct Household: Codable, Identifiable {
    var id: String                     // e.g. "HH-A3KZ9P"
    var name: String                   // e.g. "The Henderson House"
    var ownerUserID: String
    var members: [HouseholdMembership]
    var createdAt: Date

    var displayName: String { name.isEmpty ? "My Household" : name }
}

// MARK: - HouseholdMembership

struct HouseholdMembership: Codable, Identifiable {
    var id: String          // String form of the User's UUID  (user.id.uuidString)
    var username: String    // display name shown to other members
    var email: String
    var role: HouseholdRole
    var avatarHex: String   // hex color string, e.g. "#4CAF74"
    var joinedAt: Date
}

// MARK: - HouseholdRole

enum HouseholdRole: String, Codable, CaseIterable {
    case owner = "Owner"
    case adult = "Adult"
    case teen  = "Teen"
    case child = "Child"

    var icon: String {
        switch self {
        case .owner: return "crown.fill"
        case .adult: return "person.fill"
        case .teen:  return "person.crop.circle"
        case .child: return "figure.child"
        }
    }

    /// Whether this role can remove members.
    var canManage: Bool { self == .owner }

    /// Whether this role can invite new members. Restricted to Owner only.
    var canInvite: Bool { self == .owner }
}

// MARK: - HouseholdInviteRecord
//
// Named `HouseholdInviteRecord` (not `HouseholdInvite`) to avoid a
// redeclaration conflict with the existing HouseholdInviteService.swift.
// Once you delete that old file, you can rename this to `HouseholdInvite`
// and update the two references in HouseholdService.swift.

struct HouseholdInviteRecord: Codable, Identifiable {
    var id: String
    var householdID: String
    var householdName: String
    var inviterName: String
    var token: String         // HB-<base64url payload> — self-contained, emailed to recipient
    var inviteeEmail: String
    var role: HouseholdRole
    var createdAt: Date
    var acceptedAt: Date?

    // Short label for display in the pending-invites list (not used for validation)
    var displayCode: String { String(token.dropFirst(3).prefix(8)) }

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 60 * 60 * 24 * 7 // 7 days
    }
    var isPending: Bool { acceptedAt == nil && !isExpired }
}
