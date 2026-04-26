// HouseholdMembersView.swift
// Homvi
// Updated for Supabase: authVM.currentUser → authVM.profile (HomviProfile)
// currentUserID now derived from authVM.profile?.id
// sendInvite uses profile name instead of user.name

internal import SwiftUI
internal import Combine

// MARK: - HouseholdMembersView

struct HouseholdMembersView: View {

    @EnvironmentObject private var authVM:           AuthViewModel
    @EnvironmentObject private var householdService: HouseholdService

    @State private var showInviteSheet  = false
    @State private var showSetupView    = false
    @State private var showRenameAlert  = false
    @State private var newHouseholdName = ""
    @State private var showLeaveConfirm = false

    private let amber   = Color(red: 0.784, green: 0.573, blue: 0.165)
    private let bg      = Color(red: 0.980, green: 0.969, blue: 0.949)
    private let brown   = Color(red: 0.102, green: 0.071, blue: 0.031)
    private let muted   = Color(red: 0.478, green: 0.416, blue: 0.333)
    private let divider = Color(red: 0.902, green: 0.867, blue: 0.816)

    // MARK: - Derived helpers

    private var household: Household? { householdService.household }

    /// Current user's ID as a String, derived from the Supabase profile
    private var currentUserID: String {
        authVM.profile?.id.uuidString ?? ""
    }

    private var currentMember: HouseholdMembership? {
        household?.members.first { $0.id == currentUserID }
    }

    private var canManage: Bool { currentMember?.role.canManage ?? false }

    // MARK: - Body

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            if household == nil {
                noHouseholdState
            } else {
                householdContent
            }
        }
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showInviteSheet) {
            HouseholdInviteSheet()
                .environmentObject(authVM)
                .environmentObject(householdService)
        }
        .sheet(isPresented: $showSetupView) {
            HouseholdSetupView()
                .environmentObject(authVM)
                .environmentObject(householdService)
        }
        .alert("Rename Household", isPresented: $showRenameAlert) {
            TextField("New name", text: $newHouseholdName)
            Button("Save")                  { doRename() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Leave Household?", isPresented: $showLeaveConfirm) {
            Button("Leave", role: .destructive) { doLeave() }
            Button("Cancel", role: .cancel)     { }
        } message: {
            Text("You'll lose access to all shared household data on this device.")
        }
    }

    // MARK: - No household state

    private var noHouseholdState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "house.and.flag")
                .font(.system(size: 60))
                .foregroundStyle(amber)
            Text("No Household Yet")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(brown)
            Text("Create a household so your family can share meals, budgets, and schedules — each with their own login.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showSetupView = true } label: {
                Text("Set Up Household")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(amber)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Main content

    private var householdContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                householdHeader
                membersSection
                pendingInvitesSection
                dangerSection
            }
            .padding(20)
        }
    }

    // MARK: - Header card

    private var householdHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "house.fill")
                .font(.system(size: 36))
                .foregroundStyle(amber)
            Text(household?.displayName ?? "My Household")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(brown)
            let count = household?.members.count ?? 0
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill").font(.system(size: 12))
                Text("\(count) member\(count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(muted)
            if canManage {
                Button {
                    newHouseholdName = household?.name ?? ""
                    showRenameAlert = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(amber)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(divider, lineWidth: 1))
    }

    // MARK: - Members list

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MEMBERS")
                    .font(.system(size: 10, weight: .heavy)).kerning(1.4)
                    .foregroundStyle(muted)
                Spacer()
                if canManage {
                    Button { showInviteSheet = true } label: {
                        Label("Invite", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(amber)
                    }
                }
            }
            ForEach(household?.members ?? []) { member in
                memberRow(member)
            }
        }
    }

    private func memberRow(_ member: HouseholdMembership) -> some View {
        HStack(spacing: 14) {
            avatarCircle(
                hex: member.avatarHex,
                initial: member.username.first.map(String.init) ?? "?"
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.username)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(brown)
                    if member.id == currentUserID {
                        Text("You")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(amber)
                            .cornerRadius(4)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: member.role.icon).font(.system(size: 10))
                    Text(member.role.rawValue).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(muted)
            }

            Spacer()

            if canManage && member.id != currentUserID && member.role != .owner {
                Button { doRemoveMember(member.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.red.opacity(0.7))
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(divider, lineWidth: 1))
    }

    private func avatarCircle(hex: String, initial: String) -> some View {
        ZStack {
            Circle()
                .fill(colorFromHex(hex))
                .frame(width: 44, height: 44)
            Text(initial.uppercased())
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return amber }
        return Color(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }

    // MARK: - Pending invites

    @ViewBuilder
    private var pendingInvitesSection: some View {
        let pending = householdService.pendingInvites.filter { $0.isPending }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("PENDING INVITES")
                    .font(.system(size: 10, weight: .heavy)).kerning(1.4)
                    .foregroundStyle(muted)
                ForEach(pending) { invite in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(invite.inviteeEmail)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(brown)
                            HStack(spacing: 4) {
                                Text("Code: \(invite.displayCode)…")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(amber)
                                Text("· \(invite.role.rawValue)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(muted)
                            }
                        }
                        Spacer()
                        Button { householdService.revokeInvite(id: invite.id) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.red.opacity(0.7))
                        }
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.06))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Leave button

    private var dangerSection: some View {
        Button { showLeaveConfirm = true } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Leave Household").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.07))
            .cornerRadius(12)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func doRename() {
        let trimmed = newHouseholdName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? householdService.renameHousehold(trimmed, requestingUserID: currentUserID)
    }

    private func doRemoveMember(_ memberID: String) {
        try? householdService.removeMember(
            memberID: memberID,
            requestingUserID: currentUserID
        )
    }

    private func doLeave() {
        householdService.leaveHousehold(userID: currentUserID)
    }
}

// MARK: - HouseholdInviteSheet

struct HouseholdInviteSheet: View {

    @EnvironmentObject private var authVM:           AuthViewModel
    @EnvironmentObject private var householdService: HouseholdService
    @Environment(\.dismiss) private var dismiss

    @State private var email          = ""
    @State private var role: HouseholdRole = .adult
    @State private var errorMessage: String?
    @State private var didSend        = false

    private let amber   = Color(red: 0.784, green: 0.573, blue: 0.165)
    private let bg      = Color(red: 0.980, green: 0.969, blue: 0.949)
    private let brown   = Color(red: 0.102, green: 0.071, blue: 0.031)
    private let muted   = Color(red: 0.478, green: 0.416, blue: 0.333)
    private let divider = Color(red: 0.902, green: 0.867, blue: 0.816)
    private let green   = Color(red: 0.298, green: 0.686, blue: 0.455)

    // Inviter name and ID derived from Supabase profile
    private var inviterName: String {
        authVM.profile?.fullName ?? "A Homvi member"
    }
    private var inviterID: String {
        authVM.profile?.id.uuidString ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if didSend { successView } else { formView }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Form

    private var formView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("EMAIL ADDRESS")
                    .font(.system(size: 10, weight: .heavy)).kerning(1.4)
                    .foregroundStyle(muted)
                TextField("family@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(divider, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ROLE")
                    .font(.system(size: 10, weight: .heavy)).kerning(1.4)
                    .foregroundStyle(muted)
                HStack(spacing: 8) {
                    ForEach(HouseholdRole.allCases, id: \.self) { r in
                        Button { role = r } label: {
                            VStack(spacing: 4) {
                                Image(systemName: r.icon).font(.system(size: 18))
                                Text(r.rawValue).font(.system(size: 11, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(role == r ? amber : Color.white)
                            .foregroundStyle(role == r ? Color.white : muted)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(role == r ? amber : divider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: sendInvite) {
                Label("Send Invite", systemImage: "envelope.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        email.trimmingCharacters(in: .whitespaces).isEmpty
                            ? amber.opacity(0.5) : amber
                    )
                    .cornerRadius(14)
            }
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(green)
            Text("Invite Sent!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(brown)
            Text("An email with the invite code was opened in your Mail app. Once \(email) enters the code in Homvi, they'll join your household automatically.")
                .font(.system(size: 14))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(amber)
                .cornerRadius(14)
        }
        .padding(.top, 40)
    }

    // MARK: - Action

    private func sendInvite() {
        // Guard: profile must be loaded before sending
        guard !inviterID.isEmpty else {
            errorMessage = "Could not identify your account. Please try again."
            return
        }
        errorMessage = nil

        Task {
            do {
                try await householdService.inviteMember(
                    email:           email.trimmingCharacters(in: .whitespaces),
                    role:            role,
                    inviterName:     inviterName,
                    currentUserID:   inviterID
                )
                withAnimation { didSend = true }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
