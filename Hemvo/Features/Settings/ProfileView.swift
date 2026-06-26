// ProfileView.swift
// Hemvo
// Updated for Supabase: authVM.currentUser → authVM.profile (HemvoProfile)
// authService.loadAllUsers / updateUser / saveCurrentUserPublic all removed.
// Profile saves now go through AuthService.shared.updateProfile().

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import Foundation
internal import Combine
internal import UserNotifications
internal import LocalAuthentication

// MARK: - ProfileView
struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var prefs:  UserPreferences
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: ProfileTab = .personal

    enum ProfileTab: String, CaseIterable {
        case personal     = "Personal"
        case security     = "Security"
        case subscription = "Subscription"
        var icon: String {
            switch self {
            case .personal:     return "person.fill"
            case .security:     return "lock.fill"
            case .subscription: return "crown.fill"
            }
        }
    }

    private let amber   = Color(hex: "#C8922A") ?? .clear
    private let cream   = Color(hex: "#FAF7F2") ?? .clear
    private let brown   = Color(hex: "#1A1208") ?? .clear
    private let muted   = Color(hex: "#7A6A55") ?? .clear
    private let divider = Color(hex: "#E6DDD0") ?? .clear

    private var selectedColor: String {
        get { prefs.avatarColor }
        nonmutating set { prefs.avatarColor = newValue }
    }

    private let avatarColors = [
        "#C8922A", "#4CAF74", "#2196F3",
        "#E91E63", "#9C27B0", "#FF9800",
        "#795548", "#00BCD4"
    ]

    // Cached so they don't flash to placeholder when signOut() nils the profile.
    @State private var displayName:  String = "Hemvo User"
    @State private var initials:     String = "HV"
    @State private var displayEmail: String = ""

    private func syncProfileCache() {
        guard let p = authVM.profile else { return }
        let nameForDisplay  = p.fullName ?? p.username ?? "Hemvo User"
        displayName  = nameForDisplay
        displayEmail = p.email ?? ""
        let parts    = nameForDisplay.split(separator: " ").prefix(2)
        let joined   = parts.map { String($0.prefix(1)).uppercased() }.joined()
        initials     = joined.isEmpty ? "HV" : joined
    }

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()
                VStack(spacing: 0) {
                    heroHeader
                    tabBar
                    ScrollView(showsIndicators: false) {
                        tabContent
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 50)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear { syncProfileCache() }
        .onChange(of: authVM.profile) { _, _ in syncProfileCache() }
    }

    // MARK: - Hero Header
    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(hex: selectedColor) ?? amber,
                    (Color(hex: selectedColor) ?? amber).opacity(0.75)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            .animation(.easeInOut(duration: 0.3), value: selectedColor)

            Circle().fill(Color.white.opacity(0.07)).frame(width: 160).offset(x: 100, y: -30)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 100).offset(x: -70, y: 40)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: selectedColor) ?? amber)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.white)
                            .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 52)

                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.25)).frame(width: 58, height: 58)
                        Text(initials)
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                    }
                    .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .font(.system(size: 17, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(displayEmail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)

                // Color swatches
                HStack(spacing: 9) {
                    ForEach(avatarColors, id: \.self) { hex in
                        let isSelected = selectedColor == hex
                        Button {
                            withAnimation(.spring(response: 0.25)) { selectedColor = hex }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: hex) ?? .gray)
                                    .frame(width: 26, height: 26)
                                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                                if isSelected {
                                    Circle().stroke(Color.white, lineWidth: 2.5).frame(width: 26, height: 26)
                                    Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundColor(.white)
                                }
                            }
                            .scaleEffect(isSelected ? 1.2 : 1.0)
                            .animation(.spring(response: 0.2), value: isSelected)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .frame(height: 195)
    }

    // MARK: - Tab Bar
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                        }
                        .foregroundColor(isSelected ? (Color(hex: selectedColor) ?? amber) : muted)
                        Rectangle()
                            .fill(isSelected ? (Color(hex: selectedColor) ?? amber) : Color.clear)
                            .frame(height: 2).cornerRadius(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .personal:     WarmPersonalSection()
        case .security:     SecuritySection()
        case .subscription: SubscriptionSection()
        }
    }
}

// MARK: ── PERSONAL INFO ──────────────────────────────────────
struct WarmPersonalSection: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var prefs:  UserPreferences

    private let amber   = Color(hex: "#C8922A") ?? .clear
    private let amberBg = Color(hex: "#F5E4C3") ?? .clear
    private let brown   = Color(hex: "#1A1208") ?? .clear
    private let muted   = Color(hex: "#7A6A55") ?? .clear
    private let divider = Color(hex: "#E6DDD0") ?? .clear

    private var selectedColor: String {
        get { prefs.avatarColor }
        nonmutating set { prefs.avatarColor = newValue }
    }
    @State private var name      = ""
    @State private var username  = ""
    @State private var isSaving  = false
    @State private var showToast = false
    @State private var toastError = false
    @State private var toastMsg  = ""
    @State private var shake: CGFloat = 0
    @FocusState private var focused: PField?
    enum PField { case name, username }

    var isDirty: Bool {
        name != (authVM.profile?.fullName ?? "") ||
        username != (authVM.profile?.username ?? "") ||
        selectedColor != (authVM.profile?.avatarColor ?? "#C8922A")
    }

    var body: some View {
        VStack(spacing: 18) {
            warmLabel(icon: "person.fill", text: "ACCOUNT DETAILS")

            VStack(spacing: 0) {
                // Editable name field
                warmField(
                    label: "FULL NAME",
                    icon:  "person.fill",
                    placeholder: "Your name",
                    text:  $name,
                    field: .name,
                    keyboard: .default,
                    autocap: .words,
                    submitLabelType: .next,
                    onSubmitAction: { focused = .username }
                )
                divider.frame(height: 1).padding(.leading, 52)

                // Editable username field
                warmField(
                    label: "USERNAME",
                    icon:  "at",
                    placeholder: "your_username",
                    text:  $username,
                    field: .username,
                    keyboard: .default,
                    autocap: .never,
                    submitLabelType: .done,
                    onSubmitAction: { focused = nil }
                )
                divider.frame(height: 1).padding(.leading, 52)

                // Email — read-only
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#F5F0EB") ?? .clear).frame(width: 32, height: 32)
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(muted)
                    }
                    .padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("EMAIL ADDRESS")
                                .font(.system(size: 9, weight: .heavy)).kerning(1.2).foregroundColor(muted)
                            Text("· cannot be changed")
                                .font(.system(size: 9, weight: .medium)).foregroundColor(muted.opacity(0.6))
                        }
                        Text(authVM.profile?.email ?? "—")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(muted)
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11)).foregroundColor(muted.opacity(0.4)).padding(.trailing, 16)
                }
                .padding(.vertical, 14)
                .background(Color(hex: "#F8F4EE") ?? .clear)
            }
            .background(Color.white)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        focused != nil ? amber.opacity(0.5) : divider,
                        lineWidth: focused != nil ? 2 : 1
                    )
                    .animation(.easeInOut(duration: 0.15), value: focused != nil)
            )
            .shake(trigger: shake)

            // Account info card
            warmLabel(icon: "info.circle.fill", text: "ACCOUNT INFO")

            VStack(spacing: 0) {
                infoRow(
                    label: "Member Since",
                    value: authVM.profile?.createdAt?
                        .formatted(date: .abbreviated, time: .omitted) ?? "—"
                )
            }
            .background(Color.white)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(divider, lineWidth: 1))

            // Save button
            Button { save() } label: {
                ZStack {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 17))
                            Text("Save Changes").font(.system(size: 16, weight: .bold))
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(isDirty ? amber : Color(.systemGray4))
                .cornerRadius(16)
                .animation(.easeInOut(duration: 0.15), value: isDirty)
            }
            .disabled(!isDirty || isSaving)

            if showToast {
                HStack(spacing: 10) {
                    Image(systemName: toastError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(toastError ? .red : Color(hex: "#3D7A52") ?? .clear)
                    Text(toastMsg).font(.system(size: 14, weight: .bold)).foregroundColor(brown)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(Color.white)
                .cornerRadius(30)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            name     = authVM.profile?.fullName ?? ""
            username = authVM.profile?.username ?? ""
        }
    }

    @ViewBuilder
    private func warmField(
        label: String, icon: String, placeholder: String,
        text: Binding<String>, field: PField,
        keyboard: UIKeyboardType, autocap: TextInputAutocapitalization,
        submitLabelType: SubmitLabel = .next,
        onSubmitAction: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(focused == field ? amberBg : Color(hex: "#F5F0EB") ?? .clear)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(focused == field ? amber : muted)
            }
            .animation(.easeInOut(duration: 0.15), value: focused == field)
            .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).kerning(1.2)
                    .foregroundColor(focused == field ? amber : muted)
                    .animation(.easeInOut(duration: 0.15), value: focused == field)
                TextField(placeholder, text: text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(brown)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(autocap)
                    .autocorrectionDisabled()
                    .focused($focused, equals: field)
                    .submitLabel(submitLabelType)
                    .onSubmit { onSubmitAction?() }
            }
            Spacer()
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(muted.opacity(0.5))
                }
                .padding(.trailing, 14)
            } else {
                Spacer().frame(width: 14)
            }
        }
        .padding(.vertical, 14)
        .background(focused == field ? amberBg.opacity(0.3) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: focused == field)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundColor(muted)
            Spacer()
            Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(brown)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func warmLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundColor(muted)
            Text(text).font(.system(size: 9, weight: .heavy)).kerning(1.4).foregroundColor(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }

    // MARK: - Save to Supabase
    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { withAnimation { shake += 1 }; return }

        focused  = nil
        isSaving = true

        Task {
            do {
                try await AuthService.shared.updateProfile(
                    fullName: trimmedName,
                    username: username,
                    avatarColor: selectedColor
                )
                // Refresh local profile
                await authVM.loadProfile()
                await MainActor.run {
                    isSaving   = false
                    toastMsg   = "Profile updated!"
                    toastError = false
                    withAnimation(.spring()) { showToast = true }
                }
            } catch {
                await MainActor.run {
                    isSaving   = false
                    toastMsg   = error.localizedDescription
                    toastError = true
                    withAnimation(.spring()) { showToast = true }
                    withAnimation { shake += 1 }
                }
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { withAnimation { showToast = false } }
        }
    }
}

// MARK: - PersonalInfoSection (backwards compatibility alias)
struct PersonalInfoSection: View {
    @EnvironmentObject var authVM: AuthViewModel
    let accentColor: Color
    var body: some View { WarmPersonalSection() }
}

// MARK: ── SECURITY ───────────────────────────────────────────
struct SecuritySection: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var currentPassword  = ""
    @State private var newPassword      = ""
    @State private var confirmPassword  = ""
    @State private var isSaving         = false
    @State private var toastMessage     = ""
    @State private var toastIsError     = false
    @State private var showToast        = false
    @State private var shake: CGFloat   = 0
    @State private var biometricError   = ""
    @State private var showBiometricError = false
    @State private var isBiometricToggled = false
    @State private var saveTask: Task<Void, Never>? = nil

    @FocusState private var focusedField: PWField?
    enum PWField { case current, new, confirm }

    var hasMinLength: Bool   { newPassword.count >= 8 }
    var hasUppercase: Bool   { newPassword.contains(where: \.isUppercase) }
    var hasNumber: Bool      { newPassword.contains(where: \.isNumber) }
    var passwordsMatch: Bool { newPassword == confirmPassword && !confirmPassword.isEmpty }
    var canSave: Bool        { !currentPassword.isEmpty && hasMinLength && hasUppercase && hasNumber && passwordsMatch }

    var body: some View {
        VStack(spacing: 18) {
            biometricCard

            HStack(spacing: 6) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(Color.bpSlate)
                Text("CHANGE PASSWORD")
                    .font(.system(size: 10, weight: .heavy)).kerning(1.5).foregroundColor(Color.bpTextSub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                SecurityPasswordRow(
                    label: "Current Password", icon: "lock.fill",
                    text: $currentPassword, focused: $focusedField, tag: .current,
                    accentColor: focusedField == .current ? Color.bpSlate : Color(.systemGray3),
                    contentType: .password,
                    submitLabelType: .next,
                    onSubmitAction: { focusedField = .new }
                )
                (Color(hex: "#DDE1EE") ?? .clear).frame(height: 1).padding(.leading, 52)
                SecurityPasswordRow(
                    label: "New Password", icon: "lock.open.fill",
                    text: $newPassword, focused: $focusedField, tag: .new,
                    accentColor: focusedField == .new ? Color.bpNavy : Color(.systemGray3),
                    contentType: .newPassword,
                    submitLabelType: .next,
                    onSubmitAction: { focusedField = .confirm }
                )
                (Color(hex: "#DDE1EE") ?? .clear).frame(height: 1).padding(.leading, 52)
                SecurityPasswordRow(
                    label: "Confirm New Password", icon: "checkmark.shield.fill",
                    text: $confirmPassword, focused: $focusedField, tag: .confirm,
                    accentColor: focusedField == .confirm ? Color.bpNavy : Color(.systemGray3),
                    trailingCheck: passwordsMatch,
                    contentType: .newPassword,
                    submitLabelType: .done,
                    onSubmitAction: { focusedField = nil }
                )
            }
            .background(Color.bpSurface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        focusedField != nil ? Color.bpNavy.opacity(0.4) : Color.bpDivider,
                        lineWidth: focusedField != nil ? 2 : 1
                    )
                    .animation(.easeInOut(duration: 0.15), value: focusedField != nil)
            )
            .shadow(color: Color.bpText.opacity(0.04), radius: 6, y: 2)
            .shake(trigger: shake)

            VStack(alignment: .leading, spacing: 10) {
                Text("PASSWORD REQUIREMENTS")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.3).foregroundColor(Color.bpTextSub)
                SecurityHintRow(text: "At least 8 characters",   met: hasMinLength,   active: !newPassword.isEmpty)
                SecurityHintRow(text: "One uppercase letter",     met: hasUppercase,   active: !newPassword.isEmpty)
                SecurityHintRow(text: "One number",               met: hasNumber,      active: !newPassword.isEmpty)
                SecurityHintRow(text: "Passwords match",          met: passwordsMatch, active: !confirmPassword.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.bpSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.bpDivider, lineWidth: 1))

            Button { savePassword() } label: {
                ZStack {
                    if isSaving { ProgressView().tint(.white) }
                    else {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill").font(.system(size: 16))
                            Text("Update Password").font(.system(size: 16, weight: .bold))
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(canSave ? Color.bpNavy : Color(.systemGray4))
                .cornerRadius(16)
                .shadow(color: canSave ? Color.bpNavy.opacity(0.35) : .clear, radius: 10, y: 4)
                .animation(.easeInOut(duration: 0.15), value: canSave)
            }
            .disabled(!canSave || isSaving)

            if showToast {
                HStack(spacing: 10) {
                    Image(systemName: toastIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(toastIsError ? .red : Color(hex: "#2E7D32") ?? .clear)
                    Text(toastMessage).font(.system(size: 14, weight: .bold)).foregroundColor(Color.bpText)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(Color.bpSurface)
                .cornerRadius(30)
                .shadow(color: Color.bpText.opacity(0.1), radius: 12, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDisappear { saveTask?.cancel() }
    }

    private var biometricCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.bpNavyLight).frame(width: 40, height: 40)
                Image(systemName: authVM.biometricIcon)
                    .font(.system(size: 18, weight: .semibold)).foregroundColor(Color.bpNavy)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(authVM.biometricLabel).font(.system(size: 15, weight: .bold)).foregroundColor(Color.bpText)
                Text(isBiometricToggled ? "Enabled — tap to disable" : "Disabled — tap to enable")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(Color.bpTextSub)
            }
            Spacer()
            Toggle("", isOn: $isBiometricToggled).labelsHidden().tint(Color.bpNavy)
        }
        .padding(16)
        .background(Color.bpSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.bpDivider, lineWidth: 1))
        .shadow(color: Color.bpText.opacity(0.04), radius: 6, y: 2)
        .onAppear { isBiometricToggled = authVM.isBiometricEnabled }
        .onChange(of: isBiometricToggled) { _, newValue in
            if newValue {
                Task { @MainActor in
                    let ok = await authVM.enableBiometrics()
                    if !ok {
                        isBiometricToggled = false
                        biometricError = "\(authVM.biometricLabel) could not be enabled. Check Settings → Privacy → Hemvo."
                        showBiometricError = true
                    }
                }
            } else {
                authVM.disableBiometrics()
            }
        }
        .alert(authVM.biometricLabel, isPresented: $showBiometricError) {
            Button("OK", role: .cancel) { }
        } message: { Text(biometricError) }
    }

    private func savePassword() {
        guard canSave else { withAnimation { shake += 1 }; return }
        focusedField = nil
        isSaving     = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            let success = await authVM.changePassword(
                currentPassword: currentPassword, newPassword: newPassword)
            guard !Task.isCancelled else { return }
            isSaving = false
            if success {
                currentPassword = ""; newPassword = ""; confirmPassword = ""
                NotificationService.shared.sendPasswordChangedNotification()
                withAnimation(.spring()) {
                    toastMessage = "Password updated successfully!"
                    toastIsError = false; showToast = true
                }
            } else {
                withAnimation(.spring()) {
                    toastMessage = authVM.errorMessage ?? "Current password is incorrect."
                    toastIsError = true; showToast = true
                }
                withAnimation { shake += 1 }
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showToast = false }
        }
    }
}

// MARK: - SecurityPasswordRow
private struct SecurityPasswordRow: View {
    let label:           String
    let icon:            String
    @Binding var text:   String
    var focused:         FocusState<SecuritySection.PWField?>.Binding
    let tag:             SecuritySection.PWField
    var accentColor:     Color                  = Color.bpSlate
    var trailingCheck:   Bool                   = false
    var contentType:     UITextContentType      = .password
    var submitLabelType: SubmitLabel            = .next
    var onSubmitAction:  (() -> Void)?          = nil

    @State private var showText = false
    var isFocused: Bool { focused.wrappedValue == tag }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isFocused ? Color.bpNavyLight : Color(hex: "#F2F4FB") ?? .clear)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(accentColor)
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.5)
                    .foregroundColor(isFocused ? Color.bpNavy : Color.bpTextSub)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
                // Only one field lives in the hierarchy at a time so the two
                // views never compete for first-responder with the same tag.
                // onChange re-focuses the newly visible field to keep the keyboard up.
                ZStack(alignment: .leading) {
                    if showText {
                        TextField(label, text: $text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .textContentType(contentType)
                            .focused(focused, equals: tag)
                            .submitLabel(submitLabelType)
                            .onSubmit { onSubmitAction?() }
                    } else {
                        SecureField(label, text: $text)
                            .textContentType(contentType)
                            .focused(focused, equals: tag)
                            .submitLabel(submitLabelType)
                            .onSubmit { onSubmitAction?() }
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.bpText)
            }
            Spacer()
            HStack(spacing: 10) {
                if trailingCheck && !text.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16)).foregroundColor(Color(hex: "#2E7D32") ?? .clear)
                        .transition(.scale.combined(with: .opacity))
                }
                Button {
                    let wasFocused = isFocused
                    showText.toggle()
                    // Restore focus on the newly visible field so the keyboard stays up.
                    if wasFocused {
                        DispatchQueue.main.async { focused.wrappedValue = tag }
                    }
                } label: {
                    Image(systemName: showText ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isFocused ? Color.bpNavy : Color.bpTextSub)
                }
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(isFocused ? Color.bpNavyLight.opacity(0.4) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - SecurityHintRow
private struct SecurityHintRow: View {
    let text:   String
    let met:    Bool
    let active: Bool
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(active ? (met ? Color(hex: "#2E7D32") ?? .clear : Color.bpTextSub.opacity(0.4)) : Color.bpDivider, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if met && active {
                    Circle().fill(Color(hex: "#2E7D32") ?? .clear).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundColor(.white)
                }
            }
            .animation(.spring(response: 0.25), value: met)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(active ? (met ? Color(hex: "#2E7D32") ?? .clear : Color.bpText) : Color.bpTextSub)
                .animation(.easeInOut(duration: 0.15), value: met)
        }
    }
}

// MARK: ── SUBSCRIPTION ───────────────────────────────────────
struct SubscriptionSection: View {
    @EnvironmentObject var authVM:   AuthViewModel
    @EnvironmentObject var storeKit: StoreKitService

    @State private var showSubscription = false
    @State private var showPaywall      = false

    private var isTrial:  Bool { authVM.trialDaysRemaining > 0 }
    private var isActive: Bool { authVM.isSubscriptionActive && !isTrial }

    private var statusColor: Color {
        isTrial ? Color(hex: "#E67E22") ?? .clear : isActive ? Color(hex: "#2E7D32") ?? .clear : .red
    }
    private var statusIcon: String {
        isTrial ? "clock.fill" : isActive ? "crown.fill" : "xmark.circle.fill"
    }
    private var statusLabel: String {
        isTrial  ? "Free Trial — \(authVM.trialDaysRemaining) days left"
        : isActive ? "Premium Active"
        : "Subscription Expired"
    }
    private var statusDetail: String {
        isTrial  ? "Upgrade before your trial ends to keep full access"
        : isActive ? "Your subscription renews automatically through Apple"
        : "Renew to restore full access"
    }

    var body: some View {
        VStack(spacing: 18) {
            if authVM.isOwner { ownerContent } else { memberContent }
        }
        .sheet(isPresented: $showSubscription) { SubscriptionStatusView() }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
    }

    private var ownerContent: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: statusIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(statusColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusLabel)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.bpText)
                    Text(statusDetail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.bpTextSub)
                }
                Spacer()
            }
            .padding(16)
            .background(Color.bpSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(statusColor.opacity(0.2), lineWidth: 1))
            .shadow(color: Color.bpText.opacity(0.04), radius: 6, y: 2)

            Button {
                isActive ? (showSubscription = true) : (showPaywall = true)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isActive ? "creditcard.fill" : "crown.fill")
                        .font(.system(size: 16))
                    Text(isActive ? "Manage Subscription" : "Upgrade to Premium")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(isActive ? Color.bpNavy : Color(hex: "#E67E22") ?? .clear)
                .cornerRadius(16)
                .shadow(color: (isActive ? Color.bpNavy : Color(hex: "#E67E22") ?? .clear).opacity(0.35), radius: 10, y: 4)
            }

            if isActive {
                Button { Task { await storeKit.restorePurchases() } } label: {
                    Text("Restore Purchases")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.bpTextSub)
                }
            }

            Text("Subscriptions are billed through Apple. Manage or cancel anytime in your Apple ID settings.")
                .font(.caption)
                .foregroundColor(Color.bpTextSub)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
    }

    private var memberContent: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bpNavy.opacity(0.08))
                    .frame(width: 56, height: 56)
                Image(systemName: "house.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Color.bpNavy)
            }
            Text("Managed by Household Owner")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color.bpText)
            Text("Your access is included in the household subscription. Billing is handled by the household owner.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.bpTextSub)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.bpSurface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.bpDivider, lineWidth: 1))
        .shadow(color: Color.bpText.opacity(0.04), radius: 6, y: 2)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
        .environmentObject(UserPreferences.shared)
        .environmentObject(StoreKitService.shared)
}
