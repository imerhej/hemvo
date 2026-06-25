// ResetPasswordView.swift
// Hemvo
//
// Shown after the user clicks the Supabase password-reset email link.
// Supabase handles token validation automatically via the deep link session —
// by the time this view appears the user already has a valid recovery session.
// We just call AuthService.shared.resetPassword(to:) directly.

internal import SwiftUI

struct ResetPasswordView: View {

    var onComplete: () -> Void   // called when reset is done or cancelled

    @State private var newPassword  = ""
    @State private var confirmPass  = ""
    @State private var showNew      = false
    @State private var showConfirm  = false
    @State private var isLoading    = false
    @State private var errorMessage = ""
    @State private var isSuccess    = false

    // MARK: - Focus State
    private enum Field { case newPassword, confirmPassword }
    @FocusState private var focus: Field?

    // Validation
    private var hasMinLength:   Bool { newPassword.count >= 8 }
    private var hasUppercase:   Bool { newPassword.contains(where: \.isUppercase) }
    private var hasNumber:      Bool { newPassword.contains(where: \.isNumber) }
    private var passwordsMatch: Bool { newPassword == confirmPass && !confirmPass.isEmpty }
    private var canSubmit:      Bool { hasMinLength && hasUppercase && hasNumber && passwordsMatch }

    // Warm palette
    private let amber   = Color(hex: "#C8922A") ?? .clear
    private let brown   = Color(hex: "#1A1208") ?? .clear
    private let muted   = Color(hex: "#7A6A55") ?? .clear
    private let divider = Color(hex: "#E6DDD0") ?? .clear

    var body: some View {
        ZStack {
            (Color(hex: "#FAF7F2") ?? .clear).ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ──────────────────────────────────────
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: "#C8922A") ?? .clear, Color(hex: "#E6A83A") ?? .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea(edges: .top)

                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 180)
                        .offset(x: 110, y: -40)

                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 68, height: 68)
                            Image(systemName: isSuccess
                                  ? "checkmark.circle.fill"
                                  : "lock.rotation")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .animation(.spring(), value: isSuccess)

                        Text(isSuccess ? "Password Updated!" : "Set New Password")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 52)
                    .padding(.bottom, 22)
                }
                .frame(height: 180)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        if isSuccess {
                            successState
                        } else {
                            resetForm
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focus = .newPassword
            }
        }
    }

    // MARK: - Reset Form
    private var resetForm: some View {
        VStack(spacing: 20) {
            Text("Choose a new password for your Hemvo account.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(muted)
                .multilineTextAlignment(.center)

            // New password field
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("NEW PASSWORD")
                HStack {
                    Group {
                        if showNew {
                            TextField("Min 8 chars, 1 uppercase, 1 number",
                                      text: $newPassword)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focus, equals: .newPassword)
                                .submitLabel(.next)
                                .onSubmit { focus = .confirmPassword }
                        } else {
                            SecureField("Min 8 chars, 1 uppercase, 1 number",
                                        text: $newPassword)
                                .focused($focus, equals: .newPassword)
                                .submitLabel(.next)
                                .onSubmit { focus = .confirmPassword }
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(brown)

                    Button { withAnimation { showNew.toggle() } } label: {
                        Image(systemName: showNew ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(muted)
                    }
                }
                .padding(14)
                .background(Color.white)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(divider, lineWidth: 1)
                )
            }

            // Confirm password field
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("CONFIRM PASSWORD")
                HStack {
                    Group {
                        if showConfirm {
                            TextField("Repeat new password", text: $confirmPass)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focus, equals: .confirmPassword)
                                .submitLabel(.done)
                                .onSubmit { focus = nil }
                        } else {
                            SecureField("Repeat new password", text: $confirmPass)
                                .focused($focus, equals: .confirmPassword)
                                .submitLabel(.done)
                                .onSubmit { focus = nil }
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(brown)

                    Button { withAnimation { showConfirm.toggle() } } label: {
                        Image(systemName: showConfirm ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(muted)
                    }
                }
                .padding(14)
                .background(Color.white)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            !confirmPass.isEmpty
                                ? (passwordsMatch
                                   ? Color.green.opacity(0.5)
                                   : Color.red.opacity(0.4))
                                : divider,
                            lineWidth: 1.5
                        )
                )
            }

            // Password checklist
            VStack(alignment: .leading, spacing: 8) {
                checkRow(text: "At least 8 characters", met: hasMinLength)
                checkRow(text: "One uppercase letter",  met: hasUppercase)
                checkRow(text: "One number",            met: hasNumber)
                checkRow(text: "Passwords match",       met: passwordsMatch)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(amber.opacity(0.06))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(amber.opacity(0.15), lineWidth: 1)
            )

            // Error
            if !errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Submit button
            Button { performReset() } label: {
                ZStack {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 16))
                            Text("Update Password")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(canSubmit ? amber : Color(hex: "#C5C0B8") ?? .clear)
                .cornerRadius(16)
                .shadow(
                    color: canSubmit ? amber.opacity(0.4) : .clear,
                    radius: 10, y: 4
                )
                .animation(.easeInOut(duration: 0.15), value: canSubmit)
            }
            .disabled(!canSubmit || isLoading)
        }
    }

    // MARK: - Success State
    private var successState: some View {
        VStack(spacing: 18) {
            Text("Your password has been updated. You can now sign in with your new password.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(muted)
                .multilineTextAlignment(.center)

            Button { onComplete() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                    Text("Go to Sign In")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Color(hex: "#3D7A52") ?? .clear)
                .cornerRadius(16)
                .shadow(
                    color: Color(hex: "#3D7A52") ?? .clear.opacity(0.4),
                    radius: 10, y: 4
                )
            }
        }
    }

    // MARK: - Reset Logic
    // Supabase has already validated the token via the deep link —
    // the user has an active recovery session, so we just update the password.
    private func performReset() {
        guard canSubmit else { return }
        isLoading    = true
        errorMessage = ""

        Task {
            do {
                try await AuthService.shared.resetPassword(to: newPassword)
                // Clear sensitive state from memory immediately on success.
                newPassword = ""
                confirmPass = ""
                isLoading   = false
                withAnimation(.spring()) { isSuccess = true }
            } catch {
                isLoading    = false
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).kerning(1.3)
            .foregroundColor(muted)
    }

    private func checkRow(text: String, met: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(met ? Color(hex: "#3D7A52") ?? .clear : divider, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if met {
                    Circle()
                        .fill(Color(hex: "#3D7A52") ?? .clear)
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                }
            }
            .animation(.spring(response: 0.25), value: met)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(met ? Color(hex: "#3D7A52") ?? .clear : brown)
                .animation(.easeInOut(duration: 0.15), value: met)
        }
    }
}

#Preview {
    ResetPasswordView {}
}
