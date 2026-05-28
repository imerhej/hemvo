// HouseholdSetupView.swift
// Hemvo
// Updated for Supabase: authVM.currentUser → authVM.profile (HemvoProfile)

internal import SwiftUI
internal import Combine

struct HouseholdSetupView: View {

    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var householdService = HouseholdService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var mode: SetupMode      = .choose
    @State private var householdName        = ""
    @State private var joinCode             = ""
    @State private var errorMessage: String?
    @State private var isLoading            = false
    @State private var showSuccess          = false
    @State private var successMessage       = ""

    @FocusState private var nameFocused: Bool
    @FocusState private var codeFocused: Bool

    private enum SetupMode { case choose, create, join }

    private let amber   = Color(red: 0.784, green: 0.573, blue: 0.165)
    private let bg      = Color(red: 0.980, green: 0.969, blue: 0.949)
    private let brown   = Color(red: 0.102, green: 0.071, blue: 0.031)
    private let muted   = Color(red: 0.478, green: 0.416, blue: 0.333)
    private let divider = Color(red: 0.902, green: 0.867, blue: 0.816)

    // MARK: - Profile helpers (Supabase)
    // userID is populated from the session token immediately after sign-in,
    // so profileID works even before the profiles table round-trip finishes.
    private var profileID: String    { authVM.profile?.id.uuidString ?? authVM.userID?.uuidString ?? "" }
    private var profileName: String  { authVM.profile?.fullName ?? "Member" }
    private var profileEmail: String { authVM.profile?.email ?? "" }

    // MARK: - Body

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 24)
                    switch mode {
                    case .choose: choosePanel
                    case .create: createPanel
                    case .join:   joinPanel
                    }
                    Spacer(minLength: 32)
                    signOutButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("Let's go!") { dismiss() }
        } message: {
            Text(successMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.fill")
                .font(.system(size: 52))
                .foregroundStyle(amber)
                .padding(.top, 48)

            Text("Set Up Your Household")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(brown)

            Text("Everyone in your home shares the same meals, budget, grocery list, and schedule — each with their own login.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Choose Panel

    private var choosePanel: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 32)
            modeCard(
                icon: "plus.circle.fill",
                title: "Create a Household",
                subtitle: "Start fresh. You'll be the owner and can invite family members.",
                action: { withAnimation { mode = .create } }
            )
            modeCard(
                icon: "link.circle.fill",
                title: "Join a Household",
                subtitle: "Enter the invite code a family member sent you.",
                action: { withAnimation { mode = .join } }
            )
        }
    }

    private func modeCard(
        icon: String, title: String, subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(amber)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(brown)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(muted)
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create Panel

    private var createPanel: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 28)
            VStack(alignment: .leading, spacing: 8) {
                Text("HOUSEHOLD NAME")
                    .font(.system(size: 10, weight: .heavy)).kerning(1.4)
                    .foregroundStyle(muted)
                TextField("e.g. The Henderson House", text: $householdName)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(nameFocused ? amber : divider, lineWidth: nameFocused ? 1.5 : 1))
                    .font(.system(size: 15, weight: .medium))
            }
            if let err = errorMessage { errorBanner(err) }
            Button(action: createHousehold) {
                primaryLabel("Create Household", loading: isLoading)
            }
            .disabled(
                householdName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
            )
            backButton
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                nameFocused = true
            }
        }
    }

    // MARK: - Join Panel

    private var joinPanel: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 28)
            VStack(alignment: .leading, spacing: 8) {
                Text("INVITE CODE")
                    .font(.system(size: 10, weight: .heavy)).kerning(1.4)
                    .foregroundStyle(muted)
                TextField("Paste invite token (HB-…)", text: $joinCode)
                    .focused($codeFocused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(codeFocused ? amber : divider, lineWidth: codeFocused ? 1.5 : 1))
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.leading)
                Text("Paste the invite token from the email your family member sent you.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(muted)
            }
            if let err = errorMessage { errorBanner(err) }
            let trimmed = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let isDisabled = !trimmed.hasPrefix("HB-") || trimmed.count < 10 || isLoading
            Button(action: joinHousehold) {
                primaryLabel("Join Household", loading: isLoading)
            }
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1)
            backButton
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                codeFocused = true
            }
        }
    }

    // MARK: - Sub-components

    private var backButton: some View {
        Button {
            withAnimation { mode = .choose; errorMessage = nil }
        } label: {
            Label("Back", systemImage: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(muted)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(brown)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }

    private func primaryLabel(_ title: String, loading: Bool) -> some View {
        Group {
            if loading {
                ProgressView().tint(.white)
            } else {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(amber)
        .cornerRadius(14)
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button {
            authVM.signOut()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                Text("Sign Out")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(muted)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func createHousehold() {
        isLoading    = true
        errorMessage = nil
        Task {
            // Load profile for display name/email if not yet available.
            // profileID falls back to the session userID so the guard below
            // passes even when the profiles table round-trip hasn't finished.
            if authVM.profile == nil { await authVM.loadProfile() }
            guard !profileID.isEmpty else {
                errorMessage = "Could not identify your account. Please sign out and try again."
                isLoading    = false
                return
            }
            householdService.createHousehold(
                name:          householdName.trimmingCharacters(in: .whitespaces),
                ownerID:       profileID,
                ownerUsername: profileName,
                ownerEmail:    profileEmail
            )
            isLoading      = false
            successMessage = "Your household is ready. Invite family from Settings → Household Members."
            showSuccess    = true
        }
    }

    private func joinHousehold() {
        isLoading    = true
        errorMessage = nil
        Task {
            if authVM.profile == nil { await authVM.loadProfile() }
            guard !profileID.isEmpty else {
                errorMessage = "Could not identify your account. Please sign out and try again."
                isLoading    = false
                return
            }
            do {
                try await householdService.joinHousehold(
                    code:     joinCode.trimmingCharacters(in: .whitespacesAndNewlines),
                    userID:   profileID,
                    username: profileName,
                    email:    profileEmail
                )
                isLoading      = false
                successMessage = "You've joined the household! Shared data will appear shortly."
                showSuccess    = true
            } catch {
                errorMessage = error.localizedDescription
                isLoading    = false
            }
        }
    }
}
