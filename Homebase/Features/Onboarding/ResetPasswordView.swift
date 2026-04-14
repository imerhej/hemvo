//  ResetPasswordView.swift
//  HomeBase
//  Shown when the user taps the homebase://reset-password?token=… deep link.
//  Validates the token then lets the user set a new password.

internal import SwiftUI

struct ResetPasswordView: View {

    let token: String
    var onComplete: () -> Void   // called when reset is done or cancelled

    @State private var newPassword    = ""
    @State private var confirmPass    = ""
    @State private var showNew        = false
    @State private var showConfirm    = false
    @State private var isLoading      = false
    @State private var errorMessage   = ""
    @State private var isSuccess      = false
    @State private var tokenInvalid   = false

    // Validation
    private var hasMinLength: Bool  { newPassword.count >= 8 }
    private var hasUppercase: Bool  { newPassword.contains(where: \.isUppercase) }
    private var hasNumber: Bool     { newPassword.contains(where: \.isNumber) }
    private var passwordsMatch: Bool { newPassword == confirmPass && !confirmPass.isEmpty }
    private var canSubmit: Bool     { hasMinLength && hasUppercase && hasNumber && passwordsMatch }

    // Warm palette
    private let amber   = Color(hex: "#C8922A")!
    private let amberBg = Color(hex: "#F5E4C3")!
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let divider = Color(hex: "#E6DDD0")!

    var body: some View {
        ZStack {
            Color(hex: "#FAF7F2")!.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: "#C8922A")!, Color(hex: "#E6A83A")!],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea(edges: .top)

                    Circle().fill(Color.white.opacity(0.07)).frame(width: 180).offset(x: 110, y: -40)

                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.2)).frame(width: 68, height: 68)
                            Image(systemName: isSuccess ? "checkmark.circle.fill" : (tokenInvalid ? "xmark.circle.fill" : "lock.rotation"))
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .animation(.spring(), value: isSuccess)

                        Text(isSuccess ? "Password Updated!" : (tokenInvalid ? "Link Expired" : "Set New Password"))
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 52)
                    .padding(.bottom, 22)
                }
                .frame(height: 180)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        if tokenInvalid {
                            invalidTokenState
                        } else if isSuccess {
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
        .onAppear { validateToken() }
    }

    // MARK: - Token Validation
    private func validateToken() {
        let valid = PasswordResetService.shared.validate(token: token) != nil
        if !valid { tokenInvalid = true }
    }

    // MARK: - Reset Form
    private var resetForm: some View {
        VStack(spacing: 20) {
            Text("Choose a new password for your HomeBase account.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(muted)
                .multilineTextAlignment(.center)

            // New password field
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("NEW PASSWORD")
                HStack {
                    Group {
                        if showNew {
                            TextField("Min 8 chars, 1 uppercase, 1 number", text: $newPassword)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                        } else {
                            SecureField("Min 8 chars, 1 uppercase, 1 number", text: $newPassword)
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
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(divider, lineWidth: 1))
            }

            // Confirm password field
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("CONFIRM PASSWORD")
                HStack {
                    Group {
                        if showConfirm {
                            TextField("Repeat new password", text: $confirmPass)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                        } else {
                            SecureField("Repeat new password", text: $confirmPass)
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
                        .stroke(!confirmPass.isEmpty
                            ? (passwordsMatch ? Color.green.opacity(0.5) : Color.red.opacity(0.4))
                            : divider,
                            lineWidth: 1.5)
                )
            }

            // Password checklist
            VStack(alignment: .leading, spacing: 8) {
                checkRow(text: "At least 8 characters",  met: hasMinLength)
                checkRow(text: "One uppercase letter",   met: hasUppercase)
                checkRow(text: "One number",             met: hasNumber)
                checkRow(text: "Passwords match",        met: passwordsMatch)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(amber.opacity(0.06))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(amber.opacity(0.15), lineWidth: 1))

            // Error
            if !errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    Text(errorMessage).font(.system(size: 13)).foregroundColor(.red)
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
                            Image(systemName: "checkmark.shield.fill").font(.system(size: 16))
                            Text("Update Password").font(.system(size: 16, weight: .bold))
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(canSubmit ? amber : Color(hex: "#C5C0B8")!)
                .cornerRadius(16)
                .shadow(color: canSubmit ? amber.opacity(0.4) : .clear, radius: 10, y: 4)
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
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 16))
                    Text("Go to Sign In").font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Color(hex: "#3D7A52")!)
                .cornerRadius(16)
                .shadow(color: Color(hex: "#3D7A52")!.opacity(0.4), radius: 10, y: 4)
            }
        }
    }

    // MARK: - Invalid Token State
    private var invalidTokenState: some View {
        VStack(spacing: 18) {
            Text("This reset link has expired or is invalid. Links are valid for 30 minutes.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(muted)
                .multilineTextAlignment(.center)

            Button { onComplete() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left.circle.fill").font(.system(size: 16))
                    Text("Back to Sign In").font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Color(hex: "#C8922A")!)
                .cornerRadius(16)
            }
        }
    }

    // MARK: - Reset Logic
    private func performReset() {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = ""

        guard let userID = PasswordResetService.shared.validate(token: token) else {
            isLoading = false
            tokenInvalid = true
            return
        }

        let svc = AuthService()
        do {
            try svc.resetPassword(for: userID, new: newPassword)
            PasswordResetService.shared.invalidate(token: token)
            isLoading = false
            withAnimation(.spring()) { isSuccess = true }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
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
                    .stroke(met ? Color(hex: "#3D7A52")! : divider, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if met {
                    Circle().fill(Color(hex: "#3D7A52")!).frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                }
            }
            .animation(.spring(response: 0.25), value: met)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(met ? Color(hex: "#3D7A52")! : brown)
                .animation(.easeInOut(duration: 0.15), value: met)
        }
    }
}

#Preview {
    ResetPasswordView(token: "preview_token") {}
}
