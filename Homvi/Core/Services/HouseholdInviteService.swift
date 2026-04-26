//  HouseholdInviteService.swift
//  Homvi
//  Manages household invitations — generates codes, persists state, opens Mail.
//
//  HOW IT WORKS
//  ─────────────────────────────────────────────────────────────────────────
//  1. Owner (premium) taps "Invite via Email" → enters invitee's name + email
//  2. App generates a 6-char alphanumeric invite code and saves HouseholdInvite
//     to UserDefaults under the owner's household ID
//  3. App opens Mail (or Messages) with a pre-filled body containing:
//       • Download link for Homvi
//       • The invite code
//       • Owner's household name
//  4. Invitee downloads the app, signs up / logs in, goes to
//     Settings → Join Household → enters the code
//  5. App validates the code locally (or via your backend in production)
//     and adds the invitee as a HouseholdMember on the owner's account
//  ─────────────────────────────────────────────────────────────────────────

internal import Foundation
internal import UIKit

// MARK: - InviteStatus
enum InviteStatus: String, Codable {
    case pending   = "Pending"
    case accepted  = "Accepted"
    case expired   = "Expired"
}

// MARK: - HouseholdInvite
struct HouseholdInvite: Codable, Identifiable, Equatable {
    let id:           UUID
    let code:         String        // 6-char alphanumeric
    var name:         String        // invitee's name
    var email:        String        // invitee's email
    var role:         String
    var avatarColorHex: String
    var status:       InviteStatus
    let sentAt:       Date
    var acceptedAt:   Date?

    init(name: String, email: String, role: String, avatarColorHex: String) {
        self.id             = UUID()
        self.code           = HouseholdInviteService.generateCode()
        self.name           = name
        self.email          = email
        self.role           = role
        self.avatarColorHex = avatarColorHex
        self.status         = .pending
        self.sentAt         = Date()
        self.acceptedAt     = nil
    }

    var isExpired: Bool {
        // Invites expire after 7 days
        Date().timeIntervalSince(sentAt) > 7 * 24 * 3600
    }

    var formattedSentDate: String {
        sentAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

// MARK: - HouseholdInviteService
final class HouseholdInviteService {

    static let shared = HouseholdInviteService()
    private let storageKey = "hb_householdInvites"
    private init() {}

    // MARK: - Pending invites
    func loadInvites() -> [HouseholdInvite] {
        guard let data   = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([HouseholdInvite].self, from: data)
        else { return [] }
        return decoded
    }

    func saveInvites(_ invites: [HouseholdInvite]) {
        guard let data = try? JSONEncoder().encode(invites) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func addInvite(_ invite: HouseholdInvite) {
        var invites = loadInvites()
        invites.append(invite)
        saveInvites(invites)
    }

    func deleteInvite(id: UUID) {
        var invites = loadInvites()
        invites.removeAll { $0.id == id }
        saveInvites(invites)
    }

    /// Validates a code entered by an invitee. Returns the matching invite if valid.
    func validate(code: String) -> HouseholdInvite? {
        let invites = loadInvites()
        guard let invite = invites.first(where: {
            $0.code.uppercased() == code.uppercased() && $0.status == .pending
        }) else { return nil }
        return invite.isExpired ? nil : invite
    }

    /// Marks an invite as accepted.
    func markAccepted(id: UUID) {
        var invites = loadInvites()
        if let idx = invites.firstIndex(where: { $0.id == id }) {
            invites[idx].status     = .accepted
            invites[idx].acceptedAt = Date()
            saveInvites(invites)
        }
    }

    // MARK: - Send via Mail
    /// Opens the system Mail app with a pre-filled invitation email.
    func sendInviteEmail(invite: HouseholdInvite, senderName: String) {
        let subject = "\(senderName) invited you to join their Homvi household"

        let body = """
Hi \(invite.name),

\(senderName) has invited you to join their household on Homvi — the all-in-one home management app.

Your invitation code is:

    \(invite.code)

Steps to join:
1. Download Homvi from the App Store:
   https://apps.apple.com/app/homvi
2. Create an account or sign in
3. Go to Settings → Join a Household
4. Enter the code above

This invitation expires in 7 days.

See you at home! 🏠
"""

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody    = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedEmail   = invite.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let mailURLString = "mailto:\(encodedEmail)?subject=\(encodedSubject)&body=\(encodedBody)"

        if let url = URL(string: mailURLString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Code generator
    static func generateCode() -> String {
        let chars  = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   // no ambiguous chars
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
