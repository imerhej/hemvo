//  ProfileView.swift
//  HomeBase
//  User profile editor — name, email, and avatar.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications
internal import LocalAuthentication

// MARK: - PaymentCard model
struct PaymentCard: Identifiable, Codable {
    let id: UUID
    var nickname: String
    var lastFour: String
    var cardType: CardType
    var expiryMonth: Int
    var expiryYear: Int
    var isDefault: Bool

    init(id: UUID = UUID(), nickname: String, lastFour: String,
         cardType: CardType, expiryMonth: Int, expiryYear: Int, isDefault: Bool = false) {
        self.id = id; self.nickname = nickname; self.lastFour = lastFour
        self.cardType = cardType; self.expiryMonth = expiryMonth
        self.expiryYear = expiryYear; self.isDefault = isDefault
    }

    enum CardType: String, Codable, CaseIterable {
        case visa = "Visa", mastercard = "Mastercard", amex = "Amex", discover = "Discover", other = "Other"
        var icon: String  { "creditcard.fill" }
        var color: Color {
            switch self {
            case .visa:       return .blue
            case .mastercard: return .orange
            case .amex:       return Color(hex: "#007B5F") ?? .green
            case .discover:   return .orange
            case .other:      return .gray
            }
        }
    }

    var displayExpiry: String { String(format: "%02d/%02d", expiryMonth, expiryYear % 100) }
    var maskedNumber: String  { "•••• •••• •••• \(lastFour)" }
}

// MARK: - ProfileView
struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: ProfileTab = .personal

    enum ProfileTab: String, CaseIterable {
        case personal = "Personal"
        case security = "Security"
        case payment  = "Payment"

        var icon: String {
            switch self {
            case .personal: return "person.fill"
            case .security: return "lock.fill"
            case .payment:  return "creditcard.fill"
            }
        }
    }

    // Warm palette
    private let amber   = Color(hex: "#C8922A")!
    private let cream   = Color(hex: "#FAF7F2")!
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let divider = Color(hex: "#E6DDD0")!

    // Persisted via UserDefaults
    @AppStorage("hb_avatarColor") private var selectedColor: String = "#C8922A"

    private let avatarColors = [
        "#C8922A", "#4CAF74", "#2196F3",
        "#E91E63", "#9C27B0", "#FF9800",
        "#795548", "#00BCD4"
    ]

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
    }

    // MARK: - Hero Header
    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color(hex: selectedColor) ?? amber, (Color(hex: selectedColor) ?? amber).opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            .animation(.easeInOut(duration: 0.3), value: selectedColor)

            Circle().fill(Color.white.opacity(0.07)).frame(width: 160).offset(x: 100, y: -30)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 100).offset(x: -70, y: 40)

            VStack(spacing: 0) {
                // Done button
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

                // Avatar + name row (horizontal to save height)
                HStack(spacing: 14) {
                    // Avatar
                    ZStack {
                        Circle().fill(Color.white.opacity(0.25)).frame(width: 58, height: 58)
                        Text(authVM.currentUser?.initials ?? "HB")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                    }
                    .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(authVM.currentUser?.name ?? "User")
                            .font(.system(size: 17, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(authVM.currentUser?.email ?? "")
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
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2.5)
                                        .frame(width: 26, height: 26)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundColor(.white)
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
                        // Underline indicator
                        Rectangle()
                            .fill(isSelected ? (Color(hex: selectedColor) ?? amber) : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
        .shadow(color: Color(hex: "#1A1208")!.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Tab Content
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .personal: WarmPersonalSection()
        case .security: SecuritySection()
        case .payment:  PaymentSection()
        }
    }
}

// MARK: ── PERSONAL INFO (Warm) ───────────────────────────────
struct WarmPersonalSection: View {
    @EnvironmentObject var authVM: AuthViewModel
    private let authService = AuthService()

    // Warm tokens
    private let amber   = Color(hex: "#C8922A")!
    private let amberBg = Color(hex: "#F5E4C3")!
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let divider = Color(hex: "#E6DDD0")!

    @State private var name       = ""
    @State private var isSaving   = false
    @State private var showToast  = false
    @State private var toastError = false
    @State private var shake: CGFloat = 0
    @FocusState private var focused: PField?
    enum PField { case name }

    var isDirty: Bool {
        name != (authVM.currentUser?.name ?? "")
    }

    var body: some View {
        VStack(spacing: 18) {

            // ── Section label ─────────────────────────────────
            warmLabel(icon: "person.fill", text: "ACCOUNT DETAILS")

            // ── Name field (editable) ─────────────────────────
            VStack(spacing: 0) {
                warmField(
                    label: "FULL NAME",
                    icon:  "person.fill",
                    placeholder: "Your name",
                    text:  $name,
                    field: .name,
                    keyboard: .default,
                    autocap: .words
                )
                divider.frame(height: 1).padding(.leading, 52)
                // Email — read-only display row
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#F5F0EB")!)
                            .frame(width: 32, height: 32)
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(muted)
                    }
                    .padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("EMAIL ADDRESS")
                                .font(.system(size: 9, weight: .heavy)).kerning(1.2)
                                .foregroundColor(muted)
                            Text("· cannot be changed")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(muted.opacity(0.6))
                        }
                        Text(authVM.currentUser?.email ?? "—")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(muted)
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(muted.opacity(0.4))
                        .padding(.trailing, 16)
                }
                .padding(.vertical, 14)
                .background(Color(hex: "#F8F4EE")!)
            }
            .background(Color.white)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(focused != nil ? amber.opacity(0.5) : divider, lineWidth: focused != nil ? 2 : 1)
                    .animation(.easeInOut(duration: 0.15), value: focused != nil)
            )
            .shadow(color: Color(hex: "#1A1208")!.opacity(0.04), radius: 6, y: 2)
            .shake(trigger: shake)

            // ── Account info card ─────────────────────────────
            warmLabel(icon: "info.circle.fill", text: "ACCOUNT INFO")

            VStack(spacing: 0) {
                infoRow(label: "Member Since",
                        value: authVM.currentUser?.trialStartDate?
                            .formatted(date: .abbreviated, time: .omitted) ?? "—")
                divider.frame(height: 1).padding(.leading, 16)
                infoRow(label: "Account ID",
                        value: String((authVM.currentUser?.id.uuidString.prefix(8) ?? "—")) + "…")
            }
            .background(Color.white)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(divider, lineWidth: 1))
            .shadow(color: Color(hex: "#1A1208")!.opacity(0.04), radius: 6, y: 2)

            // ── Save button ───────────────────────────────────
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
                .background(isDirty ? amber : Color(hex: "#C5C0B8")!)
                .cornerRadius(16)
                .shadow(color: isDirty ? amber.opacity(0.4) : .clear, radius: 10, y: 4)
                .animation(.easeInOut(duration: 0.15), value: isDirty)
            }
            .disabled(!isDirty || isSaving)

            // ── Toast ─────────────────────────────────────────
            if showToast {
                HStack(spacing: 10) {
                    Image(systemName: toastError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(toastError ? .red : Color(hex: "#3D7A52")!)
                    Text(toastError ? "Failed to save. Try again." : "Profile updated!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(brown)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(Color.white)
                .cornerRadius(30)
                .shadow(color: Color(hex: "#1A1208")!.opacity(0.1), radius: 12, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            name = authVM.currentUser?.name ?? ""
        }
    }

    // MARK: - Field builder
    @ViewBuilder
    private func warmField(
        label: String, icon: String, placeholder: String,
        text: Binding<String>, field: PField,
        keyboard: UIKeyboardType, autocap: TextInputAutocapitalization
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(focused == field ? amberBg : Color(hex: "#F5F0EB")!)
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
            }
            Spacer()
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(muted.opacity(0.5))
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
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(muted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(brown)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func warmLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(muted)
            Text(text)
                .font(.system(size: 9, weight: .heavy)).kerning(1.4)
                .foregroundColor(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            withAnimation { shake += 1 }; return
        }
        focused  = nil
        isSaving = true
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if var user = authVM.currentUser {
                user.name = name.trimmingCharacters(in: .whitespaces)
                authVM.currentUser = user
                authService.updateUser(user)
            }
            isSaving = false
            withAnimation(.spring()) { showToast = true }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { showToast = false }
        }
    }
}

// MARK: - PersonalInfoSection (kept for backwards compatibility)
struct PersonalInfoSection: View {
    @EnvironmentObject var authVM: AuthViewModel
    let accentColor: Color
    var body: some View { WarmPersonalSection() }
}

// MARK: ── SECURITY ───────────────────────────────────────────
struct SecuritySection: View {
    @EnvironmentObject var authVM: AuthViewModel

    // Password fields
    @State private var currentPassword  = ""
    @State private var newPassword      = ""
    @State private var confirmPassword  = ""

    // UI state
    @State private var isSaving         = false
    @State private var toastMessage     = ""
    @State private var toastIsError     = false
    @State private var showToast        = false
    @State private var shake: CGFloat   = 0
    @State private var biometricError   = ""
    @State private var showBiometricError = false

    @FocusState private var focusedField: PWField?
    enum PWField { case current, new, confirm }

    // Validation
    var hasMinLength: Bool    { newPassword.count >= 8 }
    var hasUppercase: Bool    { newPassword.contains(where: \.isUppercase) }
    var hasNumber: Bool       { newPassword.contains(where: \.isNumber) }
    var passwordsMatch: Bool  { newPassword == confirmPassword && !confirmPassword.isEmpty }
    var canSave: Bool         { !currentPassword.isEmpty && hasMinLength && passwordsMatch }

    var body: some View {
        VStack(spacing: 18) {

            // ── Face ID / Touch ID ────────────────────────────
            biometricCard

            // ── Change Password header ────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.bpSlate)
                Text("CHANGE PASSWORD")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.5)
                    .foregroundColor(Color.bpTextSub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ── Password fields card ──────────────────────────
            VStack(spacing: 0) {
                SecurityPasswordRow(
                    label: "Current Password",
                    icon:  "lock.fill",
                    text:  $currentPassword,
                    focused: $focusedField,
                    tag:   .current,
                    accentColor: focusedField == .current ? Color.bpSlate : Color(.systemGray3)
                )

                Color(hex: "#DDE1EE")!.frame(height: 1).padding(.leading, 52)

                SecurityPasswordRow(
                    label: "New Password",
                    icon:  "lock.open.fill",
                    text:  $newPassword,
                    focused: $focusedField,
                    tag:   .new,
                    accentColor: focusedField == .new ? Color.bpNavy : Color(.systemGray3)
                )

                Color(hex: "#DDE1EE")!.frame(height: 1).padding(.leading, 52)

                SecurityPasswordRow(
                    label: "Confirm New Password",
                    icon:  "checkmark.shield.fill",
                    text:  $confirmPassword,
                    focused: $focusedField,
                    tag:   .confirm,
                    accentColor: focusedField == .confirm ? Color.bpNavy : Color(.systemGray3),
                    trailingCheck: passwordsMatch
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

            // ── Validation checklist ──────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("PASSWORD REQUIREMENTS")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(1.3)
                    .foregroundColor(Color.bpTextSub)

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

            // ── Update Password button ────────────────────────
            Button { savePassword() } label: {
                ZStack {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 16))
                            Text("Update Password")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(canSave ? Color.bpNavy : Color.bpDivider)
                .cornerRadius(16)
                .shadow(color: canSave ? Color.bpNavy.opacity(0.35) : .clear, radius: 10, y: 4)
                .animation(.easeInOut(duration: 0.15), value: canSave)
            }
            .disabled(!canSave || isSaving)

            // ── Toast ─────────────────────────────────────────
            if showToast {
                HStack(spacing: 10) {
                    Image(systemName: toastIsError
                          ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(toastIsError ? .red : Color(hex: "#2E7D32")!)
                    Text(toastMessage)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.bpText)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.bpSurface)
                .cornerRadius(30)
                .shadow(color: Color.bpText.opacity(0.1), radius: 12, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Biometric Card
    private var biometricCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.bpNavyLight)
                    .frame(width: 40, height: 40)
                Image(systemName: authVM.biometricIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.bpNavy)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(authVM.biometricLabel)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.bpText)
                Text(authVM.isBiometricEnabled ? "Enabled — tap to disable" : "Disabled — tap to enable")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.bpTextSub)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { authVM.isBiometricEnabled },
                set: { newVal in
                    if newVal {
                        Task {
                            let ok = await authVM.enableBiometrics()
                            if !ok {
                                biometricError = "\(authVM.biometricLabel) could not be enabled. Check Settings → Privacy."
                                showBiometricError = true
                            }
                        }
                    } else {
                        authVM.disableBiometrics()
                    }
                }
            ))
            .labelsHidden()
            .tint(Color.bpNavy)
        }
        .padding(16)
        .background(Color.bpSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.bpDivider, lineWidth: 1))
        .shadow(color: Color.bpText.opacity(0.04), radius: 6, y: 2)
        .alert(authVM.biometricLabel, isPresented: $showBiometricError) {
            Button("OK", role: .cancel) { }
        } message: { Text(biometricError) }
    }

    // MARK: - Save
    private func savePassword() {
        guard canSave else { withAnimation { shake += 1 }; return }
        focusedField = nil
        isSaving     = true
        Task {
            let success = await authVM.changePassword(current: currentPassword, new: newPassword)
            isSaving = false
            if success {
                currentPassword = ""; newPassword = ""; confirmPassword = ""
                withAnimation(.spring()) {
                    toastMessage = "Password updated successfully!"
                    toastIsError = false
                    showToast    = true
                }
            } else {
                withAnimation(.spring()) {
                    toastMessage = "Current password is incorrect."
                    toastIsError = true
                    showToast    = true
                }
                withAnimation { shake += 1 }
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { showToast = false }
        }
    }
}

// MARK: - SecurityPasswordRow
private struct SecurityPasswordRow: View {
    let label:       String
    let icon:        String
    @Binding var text: String
    var focused:     FocusState<SecuritySection.PWField?>.Binding
    let tag:         SecuritySection.PWField
    var accentColor: Color = Color.bpSlate
    var trailingCheck: Bool = false

    @State private var showText = false

    var isFocused: Bool { focused.wrappedValue == tag }

    var body: some View {
        HStack(spacing: 14) {
            // Leading icon
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isFocused ? Color.bpNavyLight : Color(hex: "#F2F4FB")!)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)

            // Label + field stacked
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(0.5)
                    .foregroundColor(isFocused ? Color.bpNavy : Color.bpTextSub)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)

                Group {
                    if showText {
                        TextField(label, text: $text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField(label, text: $text)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.bpText)
                .focused(focused, equals: tag)
            }

            Spacer()

            HStack(spacing: 10) {
                // Trailing checkmark when confirmed
                if trailingCheck && !text.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "#2E7D32")!)
                        .transition(.scale.combined(with: .opacity))
                }

                // Eye toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showText.toggle() }
                } label: {
                    Image(systemName: showText ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isFocused ? Color.bpNavy : Color.bpTextSub)
                }
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(isFocused ? Color.bpNavyLight.opacity(0.4) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - SecurityHintRow
private struct SecurityHintRow: View {
    let text:   String
    let met:    Bool
    let active: Bool   // only show coloured state once user has started typing

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(
                        active ? (met ? Color(hex: "#2E7D32")! : Color.bpTextSub.opacity(0.4)) : Color.bpDivider,
                        lineWidth: 1.5
                    )
                    .frame(width: 18, height: 18)

                if met && active {
                    Circle()
                        .fill(Color(hex: "#2E7D32")!)
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                }
            }
            .animation(.spring(response: 0.25), value: met)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(
                    active
                        ? (met ? Color(hex: "#2E7D32")! : Color.bpText)
                        : Color.bpTextSub
                )
                .animation(.easeInOut(duration: 0.15), value: met)
        }
    }
}

// MARK: ── PAYMENT ────────────────────────────────────────────
struct PaymentSection: View {
    @State private var cards: [PaymentCard]      = []
    @State private var showAddCard               = false
    @State private var cardToDelete: PaymentCard? = nil
    @State private var showDeleteAlert           = false
    private let storageKey = "hb_paymentCards"

    var body: some View {
        VStack(spacing: 16) {
            if cards.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundColor(Color(.systemGray3))
                    Text("No Payment Methods").font(.headline)
                    Text("Add a card to manage your HomeBase subscription.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(30)
                .background(Color(.systemBackground))
                .cornerRadius(18)
            } else {
                VStack(spacing: 12) {
                    ForEach(cards) { card in
                        PaymentCardRow(
                            card: card,
                            onSetDefault: { setDefault(card) },
                            onDelete: { cardToDelete = card; showDeleteAlert = true }
                        )
                    }
                }
            }

            Button { showAddCard = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 18))
                    Text("Add Payment Method").font(.headline).bold()
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.blue)
                .cornerRadius(16)
                .shadow(color: Color.blue.opacity(0.4), radius: 10, y: 5)
            }

            Text("Billing handled securely through Apple's In-App Purchase system.\nCard details are never stored on our servers.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .onAppear { loadCards() }
        .sheet(isPresented: $showAddCard) {
            AddPaymentCardSheet { newCard in
                cards.append(newCard)
                if cards.count == 1 { cards[0].isDefault = true }
                saveCards()
            }
        }
        .alert("Remove Card", isPresented: $showDeleteAlert) {
            Button("Remove", role: .destructive) { if let c = cardToDelete { removeCard(c) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Remove \(cardToDelete.map { "•••• \($0.lastFour)" } ?? "this card")?")
        }
    }

    private func setDefault(_ card: PaymentCard) {
        for i in cards.indices { cards[i].isDefault = cards[i].id == card.id }
        saveCards()
    }
    private func removeCard(_ card: PaymentCard) {
        cards.removeAll { $0.id == card.id }
        if !cards.isEmpty && !cards.contains(where: { $0.isDefault }) { cards[0].isDefault = true }
        saveCards()
    }
    private func saveCards() {
        if let d = try? JSONEncoder().encode(cards) { UserDefaults.standard.set(d, forKey: storageKey) }
    }
    private func loadCards() {
        if let d = UserDefaults.standard.data(forKey: storageKey),
           let s = try? JSONDecoder().decode([PaymentCard].self, from: d) { cards = s }
    }
}

// MARK: - PaymentCardRow
struct PaymentCardRow: View {
    let card: PaymentCard
    let onSetDefault: () -> Void
    let onDelete: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(card.cardType.color.opacity(0.12)).frame(width: 44, height: 32)
                Image(systemName: card.cardType.icon)
                    .foregroundColor(card.cardType.color).font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(card.nickname).font(.subheadline).bold()
                    if card.isDefault {
                        BadgeView(text: "DEFAULT", color: .homeBaseGreen, style: .filled)
                    }
                }
                Text(card.maskedNumber).font(.caption).foregroundColor(.secondary)
                Text("Expires \(card.displayExpiry)").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                if !card.isDefault { Button("Set as Default", action: onSetDefault) }
                Button("Remove Card", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .foregroundColor(.secondary).font(.title3).padding(4)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - AddPaymentCardSheet
struct AddPaymentCardSheet: View {
    let onSave: (PaymentCard) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var nickname    = ""
    @State private var lastFour    = ""
    @State private var cardType    = PaymentCard.CardType.visa
    @State private var expiryMonth = Calendar.current.component(.month, from: Date())
    @State private var expiryYear  = Calendar.current.component(.year, from: Date())

    var isValid: Bool { !nickname.isEmpty && lastFour.count == 4 && lastFour.allSatisfy(\.isNumber) }

    private var yearRange: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array(y...(y + 15))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.homeBaseBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        cardPreview.padding(.top, 8)
                        CardView(title: "Card Details", icon: "creditcard.fill", iconColor: .blue) {
                            VStack(spacing: 14) {
                                HBTextField(label: "Nickname (e.g. Personal Visa)",
                                            text: $nickname, icon: "tag")
                                HBTextField(label: "Last 4 digits", text: $lastFour,
                                            icon: "number", keyboard: .numberPad)
                                    .onChange(of: lastFour) { _, new in
                                        if new.count > 4 { lastFour = String(new.prefix(4)) }
                                    }
                                Picker("Card Type", selection: $cardType) {
                                    ForEach(PaymentCard.CardType.allCases, id: \.self) {
                                        Text($0.rawValue).tag($0)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        CardView(title: "Expiry Date", icon: "calendar", iconColor: .blue) {
                            HStack(spacing: 20) {
                                Picker("Month", selection: $expiryMonth) {
                                    ForEach(1...12, id: \.self) {
                                        Text(String(format: "%02d", $0)).tag($0)
                                    }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                                Text("/").font(.title2).foregroundColor(.secondary)
                                Picker("Year", selection: $expiryYear) {
                                    ForEach(yearRange, id: \.self) { Text(String($0)).tag($0) }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                            }
                            .frame(height: 100)
                        }
                        Button {
                            guard isValid else { return }
                            onSave(PaymentCard(nickname: nickname, lastFour: lastFour,
                                               cardType: cardType, expiryMonth: expiryMonth,
                                               expiryYear: expiryYear))
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Card").font(.headline).bold()
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(isValid ? Color.blue : Color(.systemGray4))
                            .cornerRadius(16)
                            .shadow(color: isValid ? Color.blue.opacity(0.4) : .clear, radius: 10, y: 5)
                        }
                        .disabled(!isValid)
                        Text("Only the last 4 digits are saved. Full card numbers are never stored.")
                            .font(.caption2).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                            .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Add Payment Method")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.blue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.blue)
                }
            }
        }
    }

    private var cardPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [cardType.color, cardType.color.opacity(0.7)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 160)
                .shadow(color: cardType.color.opacity(0.4), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(nickname.isEmpty ? "Card Nickname" : nickname)
                        .font(.subheadline).bold().foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(cardType.rawValue).font(.headline).bold().foregroundColor(.white)
                }
                Text("•••• •••• •••• \(lastFour.isEmpty ? "****" : lastFour)")
                    .font(.system(.title3, design: .monospaced)).foregroundColor(.white)
                HStack {
                    Text("EXPIRES").font(.caption2).foregroundColor(.white.opacity(0.7))
                    Text(String(format: "%02d/%02d", expiryMonth, expiryYear % 100))
                        .font(.caption).bold().foregroundColor(.white)
                }
            }
            .padding(20)
        }
    }
}

#Preview {
    ProfileView().environmentObject(AuthViewModel())
}
