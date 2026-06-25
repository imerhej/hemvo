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
/// Defaults vary by role: teens are excluded from financial alerts.
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
    var isDisabled: Bool

    init(id: String, username: String, email: String, role: HouseholdRole,
         avatarHex: String, joinedAt: Date, permissions: MemberPermissions? = nil,
         isDisabled: Bool = false) {
        self.id          = id
        self.username    = username
        self.email       = email
        self.role        = role
        self.avatarHex   = avatarHex
        self.joinedAt    = joinedAt
        self.permissions = permissions ?? .defaults(for: role)
        self.isDisabled  = isDisabled
    }

    // Backward-compatible decode: existing cached memberships without permissions
    // or isDisabled fall back to safe defaults so no data is lost on upgrade.
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
        isDisabled   = try c.decodeIfPresent(Bool.self,  forKey: .isDisabled) ?? false
    }
}

// MARK: - HouseholdRole

enum HouseholdRole: String, Codable, CaseIterable {
    case owner = "Owner"
    case adult = "Adult"
    case teen  = "Teen"

    var icon: String {
        switch self {
        case .owner: return "crown.fill"
        case .adult: return "person.fill"
        case .teen:  return "person.crop.circle"
        }
    }

    /// Whether this role can remove members.
    var canManage: Bool { self == .owner }

    /// Whether this role can invite new members. Restricted to Owner only.
    var canInvite: Bool { self == .owner }

    /// Whether this role can add, edit, or delete content in the app.
    var canWrite: Bool { self == .owner || self == .adult }
}

// MARK: - HouseholdInvite

struct HouseholdInvite: Codable, Identifiable {
    var id: String
    /// UUID of the row in the `household_invites` Supabase table (used for revocation).
    var supabaseID: String?
    var householdID: String
    var householdName: String
    var inviterName: String
    /// Short alphanumeric code ("ABCD-EFGH") stored server-side and emailed to the recipient.
    var code: String
    var inviteeEmail: String
    var role: HouseholdRole
    /// Owner-specified permissions applied to the member's profile when they join.
    /// nil means role-based defaults will be used.
    var permissions: MemberPermissions?
    var createdAt: Date
    var acceptedAt: Date?

    var displayCode: String { code }

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 60 * 60 * 24 * 7 // 7 days
    }
    var isPending: Bool { acceptedAt == nil && !isExpired }

    // MARK: Memberwise init

    init(id: String, supabaseID: String? = nil, householdID: String,
         householdName: String, inviterName: String, code: String,
         inviteeEmail: String, role: HouseholdRole,
         permissions: MemberPermissions? = nil,
         createdAt: Date, acceptedAt: Date? = nil) {
        self.id            = id
        self.supabaseID    = supabaseID
        self.householdID   = householdID
        self.householdName = householdName
        self.inviterName   = inviterName
        self.code          = code
        self.inviteeEmail  = inviteeEmail
        self.role          = role
        self.permissions   = permissions
        self.createdAt     = createdAt
        self.acceptedAt    = acceptedAt
    }

    // MARK: Codable — backward-compat with v1 (HMAC token) records cached in UserDefaults

    private enum CodingKeys: String, CodingKey {
        case id, supabaseID, householdID, householdName, inviterName
        case code, token        // v1 used 'token'; v2+ uses 'code'
        case inviteeEmail, role, permissions, createdAt, acceptedAt
    }

    init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self,                      forKey: .id)
        supabaseID    = try c.decodeIfPresent(String.self,             forKey: .supabaseID)
        householdID   = try c.decode(String.self,                      forKey: .householdID)
        householdName = try c.decode(String.self,                      forKey: .householdName)
        inviterName   = try c.decode(String.self,                      forKey: .inviterName)
        inviteeEmail  = try c.decode(String.self,                      forKey: .inviteeEmail)
        role          = try c.decode(HouseholdRole.self,               forKey: .role)
        permissions   = try c.decodeIfPresent(MemberPermissions.self,  forKey: .permissions)
        createdAt     = try c.decode(Date.self,                        forKey: .createdAt)
        acceptedAt    = try c.decodeIfPresent(Date.self,               forKey: .acceptedAt)

        // v2+ stores the short code; v1 stored a long HMAC-signed token.
        // Accept both so cached records survive an app update without data loss.
        // Old tokens expire within 7 days and will be pruned automatically.
        if let c2 = try? c.decode(String.self, forKey: .code), !c2.isEmpty {
            code = c2
        } else if let old = try? c.decode(String.self, forKey: .token) {
            code = String(old.dropFirst(3).prefix(9)) // display stub only
        } else {
            code = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                      forKey: .id)
        try c.encodeIfPresent(supabaseID,     forKey: .supabaseID)
        try c.encode(householdID,             forKey: .householdID)
        try c.encode(householdName,           forKey: .householdName)
        try c.encode(inviterName,             forKey: .inviterName)
        try c.encode(code,                    forKey: .code)
        try c.encode(inviteeEmail,            forKey: .inviteeEmail)
        try c.encode(role,                    forKey: .role)
        try c.encodeIfPresent(permissions,    forKey: .permissions)
        try c.encode(createdAt,               forKey: .createdAt)
        try c.encodeIfPresent(acceptedAt,     forKey: .acceptedAt)
    }
}
