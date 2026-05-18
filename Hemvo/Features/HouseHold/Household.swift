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

// MARK: - MemberPermissions

/// Per-member notification flags. Stored as JSONB in profiles.permissions.
/// Defaults vary by role: teens/children are excluded from financial alerts.
struct MemberPermissions: Codable, Equatable {
    var receiveExpenseAlerts:     Bool
    var receiveMealAlerts:        Bool
    var receiveCalendarAlerts:    Bool
    var receiveMaintenanceAlerts: Bool

    static func defaults(for role: HouseholdRole) -> MemberPermissions {
        switch role {
        case .owner, .adult:
            return MemberPermissions(receiveExpenseAlerts: true,  receiveMealAlerts: true,
                                     receiveCalendarAlerts: true,  receiveMaintenanceAlerts: true)
        case .teen:
            return MemberPermissions(receiveExpenseAlerts: false, receiveMealAlerts: true,
                                     receiveCalendarAlerts: true,  receiveMaintenanceAlerts: true)
        case .child:
            return MemberPermissions(receiveExpenseAlerts: false, receiveMealAlerts: true,
                                     receiveCalendarAlerts: true,  receiveMaintenanceAlerts: false)
        }
    }
}

// MARK: - HouseholdMembership

struct HouseholdMembership: Codable, Identifiable {
    var id: String          // String form of the User's UUID  (user.id.uuidString)
    var username: String    // display name shown to other members
    var email: String
    var role: HouseholdRole
    var avatarHex: String   // hex color string, e.g. "#4CAF74"
    var joinedAt: Date
    var permissions: MemberPermissions

    init(id: String, username: String, email: String, role: HouseholdRole,
         avatarHex: String, joinedAt: Date, permissions: MemberPermissions? = nil) {
        self.id          = id
        self.username    = username
        self.email       = email
        self.role        = role
        self.avatarHex   = avatarHex
        self.joinedAt    = joinedAt
        self.permissions = permissions ?? .defaults(for: role)
    }

    // Backward-compatible decode: existing cached memberships without permissions
    // fall back to role-based defaults so no data is lost on upgrade.
    init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self,         forKey: .id)
        username     = try c.decode(String.self,         forKey: .username)
        email        = try c.decode(String.self,         forKey: .email)
        role         = try c.decode(HouseholdRole.self,  forKey: .role)
        avatarHex    = try c.decode(String.self,         forKey: .avatarHex)
        joinedAt     = try c.decode(Date.self,           forKey: .joinedAt)
        permissions  = try c.decodeIfPresent(MemberPermissions.self, forKey: .permissions)
                       ?? .defaults(for: role)
    }
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

    /// Whether this role can add, edit, or delete content in the app.
    var canWrite: Bool { self == .owner || self == .adult }
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
    /// Owner-specified permissions applied to the member's profile when they join.
    /// nil means role-based defaults will be used.
    var permissions: MemberPermissions?
    var createdAt: Date
    var acceptedAt: Date?

    // Short label for display in the pending-invites list (not used for validation)
    var displayCode: String { String(token.dropFirst(3).prefix(8)) }

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 60 * 60 * 24 * 7 // 7 days
    }
    var isPending: Bool { acceptedAt == nil && !isExpired }
}
