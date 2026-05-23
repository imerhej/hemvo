//  OwnerLapsedView.swift
//  Hemvo
//  Shown to household members after the owner's 5-day grace period has expired.

internal import SwiftUI

struct OwnerLapsedView: View {

    @EnvironmentObject var authVM:           AuthViewModel
    @EnvironmentObject var householdService: HouseholdService

    @AppStorage("hb_avatarColor") private var avatarColor: String = "#4CAF74"

    private var accentColor: Color { Color(hex: avatarColor) ?? .homeBaseGreen }

    private var ownerName: String {
        guard let h = householdService.household else { return "the owner" }
        return h.members.first { $0.id == h.ownerUserID }?.username ?? "the owner"
    }

    var body: some View {
        ZStack {
            Color.homeBaseBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 90, height: 90)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                }

                // Message
                VStack(spacing: 12) {
                    Text("Subscription Paused")
                        .font(.system(size: 26, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("\(ownerName)'s subscription has ended. The household is paused until they renew.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Info card
                VStack(alignment: .leading, spacing: 14) {
                    LapsedInfoRow(icon: "crown.fill",       color: accentColor,  text: "Ask \(ownerName) to open the app and renew their subscription.")
                    LapsedInfoRow(icon: "arrow.triangle.2.circlepath", color: .blue, text: "Once renewed, you'll have full access immediately.")
                    LapsedInfoRow(icon: "person.badge.minus", color: .orange,    text: "You can sign out and create your own household if needed.")
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                .padding(.horizontal, 24)

                Spacer()

                // Sign Out
                Button(role: .destructive) {
                    authVM.signOut()
                } label: {
                    Text("Sign Out")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - LapsedInfoRow

private struct LapsedInfoRow: View {
    let icon:  String
    let color: Color
    let text:  String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    OwnerLapsedView()
        .environmentObject(AuthViewModel())
        .environmentObject(HouseholdService.shared)
}
