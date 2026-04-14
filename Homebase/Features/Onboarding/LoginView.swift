//  LoginView.swift
//  HomeBase
//  Sign-up / login. Eye icon on password, Face ID quick login, email verification on sign-up.

internal import SwiftUI
internal import LocalAuthentication
internal import Combine
internal import AuthenticationServices

enum AuthMode { case login, signUp }

struct LoginView: View {

    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var mode: AuthMode
    @State private var name              = ""
    @State private var email             = ""
    @State private var password          = ""
    @State private var confirmPass       = ""
    @State private var showPassword      = false
    @State private var showConfirmPass   = false
    @State private var shakeTrigger: CGFloat = 0
    @State private var appearAnim        = false

    // Email verification flow
    @State private var showVerification  = false
    @State private var verificationCode  = ""
    @State private var enteredCode       = ""
    @State private var verifyError       = false
    @State private var isSendingCode     = false
    @State private var isVerified        = false

    // Forgot password flow
    @State private var showForgotPassword  = false
    @State private var resetEmail          = ""
    @State private var resetError          = ""
    @State private var resetSuccess        = false

    init(mode: AuthMode) { _mode = State(initialValue: mode) }

    var isSignUp: Bool { mode == .signUp }

    var isFormValid: Bool {
        if isSignUp {
            return !email.isEmpty && !name.isEmpty
                && password.count >= 8
                && password.contains(where: \.isUppercase)
                && password.contains(where: \.isNumber)
                && password == confirmPass
        }
        return !email.isEmpty && !password.isEmpty
    }

    var modeGradient: [Color] {
        isSignUp
        ? [Color(hex: "#1B5E34") ?? .green, Color(hex: "#4CAF74") ?? .green]
        : [Color(hex: "#0D47A1") ?? .blue,  Color(hex: "#2196F3") ?? .blue]
    }
    var modeAccent: Color {
        isSignUp
        ? (Color(hex: "#4CAF74") ?? .green)
        : (Color(hex: "#2196F3") ?? .blue)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: modeGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: mode)

            Circle().fill(Color.white.opacity(0.05)).frame(width: 320).offset(x: 160, y: -220)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 180).offset(x: -100, y: 320)

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        brandHeader.padding(.top, 8)

                        formCard
                            .padding(.horizontal, 20)
                            .shakeLocal(trigger: shakeTrigger)

                        if let err = authVM.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(err).font(.subheadline)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .scale))
                        }

                        submitButton.padding(.horizontal, 20)

                        // Face ID button — login only, only if enabled
                        if !isSignUp && authVM.isBiometricEnabled {
                            faceIDButton.padding(.horizontal, 20)
                        }

                        toggleMode

                        HStack {
                            Rectangle().fill(Color.white.opacity(0.25)).frame(height: 0.5)
                            Text("or").font(.caption).foregroundColor(.white.opacity(0.7)).padding(.horizontal, 10)
                            Rectangle().fill(Color.white.opacity(0.25)).frame(height: 0.5)
                        }
                        .padding(.horizontal, 20)

                        socialButtons

                        if isSignUp {
                            Text("By creating an account you agree to our Terms of Service and Privacy Policy.")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.55))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        Spacer(minLength: 40)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5).delay(0.1)) { appearAnim = true }
        }
        // Email verification sheet
        .sheet(isPresented: $showVerification) {
            emailVerificationSheet
        }
        // Forgot password sheet
        .sheet(isPresented: $showForgotPassword) {
            forgotPasswordSheet
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.subheadline).bold()
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .cornerRadius(20)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Brand Header
    private var brandHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.12)).frame(width: 88, height: 88)
                Circle().fill(Color.white.opacity(0.20)).frame(width: 68, height: 68)
                Image(systemName: "house.circle.fill")
                    .font(.system(size: 38)).foregroundColor(.white)
            }
            .scaleEffect(appearAnim ? 1 : 0.6)
            .opacity(appearAnim ? 1 : 0)

            VStack(spacing: 6) {
                Text(isSignUp ? "Create Account" : "Welcome Back")
                    .font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                Text(isSignUp ? "Start your 7-day free trial today" : "Sign in to HomeBase")
                    .font(.subheadline).foregroundColor(.white.opacity(0.8))
            }
            .opacity(appearAnim ? 1 : 0)
            .offset(y: appearAnim ? 0 : 12)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: mode)
    }

    // MARK: - Form Card
    private var formCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isSignUp ? "Account Details" : "Sign In Details")
                    .font(.caption).bold().foregroundColor(modeAccent)
                Spacer()
                Image(systemName: isSignUp ? "person.badge.plus" : "lock.shield.fill")
                    .font(.caption).foregroundColor(modeAccent)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(modeAccent.opacity(0.06))

            Divider()

            VStack(spacing: 0) {
                if isSignUp {
                    LoginField(label: "Full Name", text: $name, icon: "person.fill",
                               accent: modeAccent, keyboard: .default, autocap: .words)
                    fieldDivider
                }

                LoginField(label: "Email Address", text: $email, icon: "envelope.fill",
                           accent: modeAccent, keyboard: .emailAddress)
                fieldDivider

                // Password with eye toggle
                PasswordLoginField(
                    label:       "Password",
                    text:        $password,
                    showText:    $showPassword,
                    accent:      modeAccent
                )

                if isSignUp {
                    fieldDivider
                    // Confirm password with eye toggle
                    PasswordLoginField(
                        label:    "Confirm Password",
                        text:     $confirmPass,
                        showText: $showConfirmPass,
                        accent:   modeAccent,
                        trailing: password == confirmPass && !confirmPass.isEmpty
                            ? "checkmark.circle.fill" : nil,
                        trailingColor: .homeBaseGreen
                    )
                    fieldDivider
                    // Password strength hints
                    VStack(alignment: .leading, spacing: 8) {
                        PasswordHint(text: "At least 8 characters",
                                     met: password.count >= 8)
                        PasswordHint(text: "One uppercase letter",
                                     met: password.contains(where: \.isUppercase))
                        PasswordHint(text: "One number",
                                     met: password.contains(where: \.isNumber))
                        PasswordHint(text: "Passwords match",
                                     met: password == confirmPass && !confirmPass.isEmpty)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(modeAccent.opacity(0.03))
                }
            }

            if !isSignUp {
                HStack {
                    Spacer()
                    Button("Forgot Password?") {
                        resetEmail = email
                        resetError = ""
                        resetSuccess = false
                        showForgotPassword = true
                    }
                    .font(.caption).bold().foregroundColor(modeAccent)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .animation(.easeInOut(duration: 0.25), value: mode)
    }

    private var fieldDivider: some View {
        Divider().padding(.leading, 52)
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        Button { submit() } label: {
            ZStack {
                if authVM.isLoading {
                    ProgressView().tint(modeAccent)
                } else {
                    HStack(spacing: 10) {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .font(.headline).bold()
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .foregroundColor(modeAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(modeAccent.opacity(0.3), lineWidth: 1.5))
            .opacity(isFormValid ? 1 : 0.6)
        }
        .disabled(!isFormValid || authVM.isLoading)
        .animation(.easeInOut(duration: 0.2), value: isFormValid)
    }

    // MARK: - Face ID Button
    private var faceIDButton: some View {
        Button { authenticateWithBiometrics() } label: {
            HStack(spacing: 10) {
                Image(systemName: biometricIcon)
                    .font(.system(size: 20, weight: .semibold))
                Text("Sign in with \(biometricLabel)")
                    .font(.headline).bold()
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.white.opacity(0.18))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.35), lineWidth: 1.5))
        }
    }

    // Detect Face ID vs Touch ID
    private var biometricLabel: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .faceID ? "Face ID" : "Touch ID"
    }

    private var biometricIcon: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .faceID ? "faceid" : "touchid"
    }

    private func authenticateWithBiometrics() {
        authVM.loginWithBiometrics()
    }

    // MARK: - Toggle Mode
    private var toggleMode: some View {
        HStack(spacing: 6) {
            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                .font(.subheadline).foregroundColor(.white.opacity(0.8))
            Button(isSignUp ? "Sign In" : "Sign Up") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    mode = isSignUp ? .login : .signUp
                    authVM.errorMessage = nil
                    name = ""; confirmPass = ""
                    showPassword = false; showConfirmPass = false
                }
            }
            .font(.subheadline).bold().foregroundColor(.white).underline()
        }
    }

    // MARK: - Social Buttons
    private var socialButtons: some View {
        VStack(spacing: 10) {
            // Sign in with Apple — native, no extra package needed
            Button { authVM.loginWithApple() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Continue with Apple")
                        .font(.subheadline).bold()
                }
                .foregroundColor(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.label))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 0.5))
            }

            // Sign in with Google — requires GoogleSignIn package (see SocialAuthService.swift)
            Button { authVM.loginWithGoogle() } label: {
                HStack(spacing: 10) {
                    // G logo using SF Symbols globe as fallback; swap for Image("google_logo")
                    // once you add the asset to your asset catalog
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Continue with Google")
                        .font(.subheadline).bold()
                }
                .foregroundColor(Color(.label))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 20)
        .disabled(authVM.isLoading)
    }

    // MARK: - Email Verification Sheet
    private var emailVerificationSheet: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#F4F6FB")!.ignoresSafeArea()
                VStack(spacing: 28) {
                    // Icon
                    ZStack {
                        Circle().fill(modeAccent.opacity(0.12)).frame(width: 90, height: 90)
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 40)).foregroundColor(modeAccent)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 8) {
                        Text("Verify Your Email")
                            .font(.system(size: 22, weight: .bold))
                        if isSendingCode {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8).tint(modeAccent)
                                Text("Sending code to \(email)…")
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                        } else {
                            Text("We sent a 6-digit code to\n\(email)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    // 6-digit code input
                    VStack(spacing: 10) {
                        TextField("Enter 6-digit code", text: $enteredCode)
                            .keyboardType(.numberPad)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(verifyError ? Color.red : modeAccent.opacity(0.4), lineWidth: 2)
                            )
                            .onChange(of: enteredCode) { _, new in
                                let filtered = new.filter { $0.isNumber }
                                if filtered.count > 6 { enteredCode = String(filtered.prefix(6)) }
                                else { enteredCode = filtered }
                                verifyError = false
                            }

                        if verifyError {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                Text("Incorrect code. Please try again.")
                                    .font(.caption).foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Verify button
                    Button { verifyCode() } label: {
                        Text("Verify & Continue")
                            .font(.headline).bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(enteredCode.count == 6 ? modeAccent : Color.gray.opacity(0.4))
                            .cornerRadius(14)
                    }
                    .disabled(enteredCode.count < 6)
                    .padding(.horizontal, 24)

                    // Resend
                    Button {
                        sendVerificationCode()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                            Text("Resend Code")
                        }
                        .font(.subheadline).foregroundColor(modeAccent)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Email Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showVerification = false }
                        .foregroundColor(modeAccent)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    // MARK: - Forgot Password Sheet
    private var forgotPasswordSheet: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#F4F6FB")!.ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer().frame(height: 8)

                    // Icon
                    ZStack {
                        Circle().fill(modeAccent.opacity(0.1)).frame(width: 100, height: 100)
                        Image(systemName: resetSuccess ? "checkmark.circle.fill" : "envelope.badge.fill")
                            .font(.system(size: 44))
                            .foregroundColor(resetSuccess ? .green : modeAccent)
                    }
                    .animation(.spring(response: 0.4), value: resetSuccess)

                    if resetSuccess {
                        // ── Sent state ────────────────────────
                        VStack(spacing: 10) {
                            Text("Check Your Email")
                                .font(.system(size: 24, weight: .black))
                            Text("We sent a password reset link to\n\(resetEmail)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Text("Tap the link in your email to set a new password. Check your spam folder if you don't see it.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }

                        Button { showForgotPassword = false } label: {
                            Text("Back to Sign In")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(modeAccent)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 24)

                    } else {
                        // ── Email input ───────────────────────
                        VStack(spacing: 10) {
                            Text("Forgot Password?")
                                .font(.system(size: 24, weight: .black))
                            Text("Enter your email and we'll send you\na link to reset your password.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL ADDRESS")
                                .font(.system(size: 9, weight: .heavy)).kerning(1.3)
                                .foregroundColor(.secondary)
                                .padding(.leading, 2)

                            HStack(spacing: 12) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(modeAccent)
                                    .frame(width: 20)
                                TextField("your@email.com", text: $resetEmail)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .padding(16)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(modeAccent.opacity(0.35), lineWidth: 1.5)
                            )
                            .shadow(color: modeAccent.opacity(0.08), radius: 6, y: 2)
                        }
                        .padding(.horizontal, 24)

                        if !resetError.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red).font(.system(size: 13))
                                Text(resetError)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 24)
                        }

                        Button { sendResetLink() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 15))
                                Text("Send Reset Link")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(resetEmail.contains("@") ? modeAccent : Color.gray.opacity(0.35))
                            .cornerRadius(14)
                            .animation(.easeInOut(duration: 0.15), value: resetEmail.contains("@"))
                        }
                        .disabled(!resetEmail.contains("@"))
                        .padding(.horizontal, 24)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showForgotPassword = false }
                        .foregroundColor(modeAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func sendResetLink() {
        let trimmed = resetEmail.lowercased().trimmingCharacters(in: .whitespaces)
        let svc     = AuthService()
        let users   = svc.loadAllUsers()

        guard let user = users.first(where: { $0.email.lowercased() == trimmed }) else {
            resetError = "No account found with that email address."
            return
        }

        let token    = PasswordResetService.shared.generateToken(for: user.id)
        let resetURL = "homebase://reset-password?token=\(token)"

        resetError = ""

        Task {
            // Send the real email
            let sent = await EmailService.shared.sendPasswordResetLink(
                to:        trimmed,
                resetURL:  resetURL,
                firstName: user.firstName
            )

            await MainActor.run {
                if sent {
                    withAnimation(.spring()) { resetSuccess = true }
                } else {
                    // Fallback: open Mail with pre-filled body
                    let subject = "Reset your HomeBase password"
                    let body    = "Tap to reset your password:\n\n\(resetURL)\n\nExpires in 30 minutes."
                    let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "mailto:\(trimmed)?subject=\(subjectEncoded)&body=\(encoded)") {
                        UIApplication.shared.open(url)
                    }
                    withAnimation(.spring()) { resetSuccess = true }
                }
            }
        }
    }

    // MARK: - Submit
    private func submit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        if isSignUp {
            // Send verification code first, then show sheet
            sendVerificationCode()
            showVerification = true
        } else {
            Task {
                await authVM.login(email: email, password: password)
                if authVM.errorMessage != nil {
                    withAnimation { shakeTrigger += 1 }
                }
            }
        }
    }

    private func sendVerificationCode() {
        let code = String(format: "%06d", Int.random(in: 100000...999999))
        verificationCode = code
        enteredCode      = ""
        verifyError      = false
        isSendingCode    = true

        Task {
            let sent = await EmailService.shared.sendVerificationCode(to: email, code: code)
            await MainActor.run {
                isSendingCode = false
                if !sent {
                    // Fallback: still set the code so dev can read it from the console
                    print("EmailService fallback — code for \(email): \(code)")
                }
            }
        }
    }

    private func verifyCode() {
        if enteredCode == verificationCode {
            showVerification = false
            Task {
                await authVM.signUp(name: name, email: email, password: password)
                if authVM.errorMessage != nil {
                    withAnimation { shakeTrigger += 1 }
                }
            }
        } else {
            withAnimation { verifyError = true }
        }
    }
}

// MARK: - PasswordLoginField  (password field with eye toggle)
struct PasswordLoginField: View {
    let label:      String
    @Binding var text:      String
    @Binding var showText:  Bool
    let accent:     Color
    var trailing:   String? = nil
    var trailingColor: Color = .homeBaseGreen

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 15))
                .foregroundColor(focused ? accent : Color(.systemGray3))
                .frame(width: 20)
                .padding(.leading, 16)
                .animation(.easeInOut(duration: 0.15), value: focused)

            Group {
                if showText {
                    TextField(label, text: $text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField(label, text: $text)
                }
            }
            .focused($focused)
            .font(.subheadline)
            .padding(.vertical, 16)

            // Trailing icon (checkmark) if provided
            if let t = trailing {
                Image(systemName: t)
                    .foregroundColor(trailingColor)
                    .font(.subheadline)
                    .padding(.trailing, 4)
                    .transition(.scale.combined(with: .opacity))
            }

            // Eye toggle — always shown for password fields
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showText.toggle() }
            } label: {
                Image(systemName: showText ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14))
                    .foregroundColor(focused ? accent : Color(.systemGray3))
            }
            .padding(.trailing, 14)
        }
        .background(focused ? accent.opacity(0.04) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: focused)
    }
}

// MARK: - LoginField  (non-password fields)
struct LoginField: View {
    let label:         String
    @Binding var text: String
    let icon:          String
    let accent:        Color
    var keyboard:      UIKeyboardType                 = .default
    var autocap:       TextInputAutocapitalization    = .never
    var isSecure:      Bool                           = false
    var trailingIcon:  String?                        = nil
    var trailingColor: Color                          = .homeBaseGreen

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(focused ? accent : Color(.systemGray3))
                .frame(width: 20)
                .padding(.leading, 16)
                .animation(.easeInOut(duration: 0.15), value: focused)

            Group {
                if isSecure {
                    SecureField(label, text: $text)
                } else {
                    TextField(label, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(autocap)
                        .autocorrectionDisabled()
                }
            }
            .focused($focused)
            .font(.subheadline)
            .padding(.vertical, 16)

            if let trailing = trailingIcon {
                Image(systemName: trailing)
                    .foregroundColor(trailingColor)
                    .font(.subheadline)
                    .padding(.trailing, 14)
                    .transition(.scale.combined(with: .opacity))
            } else if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(.systemGray3))
                        .font(.subheadline)
                }
                .padding(.trailing, 14)
            } else {
                Spacer().frame(width: 14)
            }
        }
        .background(focused ? accent.opacity(0.04) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: focused)
    }
}

// MARK: - PasswordHint
private struct PasswordHint: View {
    let text: String
    let met:  Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundColor(met ? (Color(hex: "#4CAF74") ?? .green) : Color(.systemGray3))
                .font(.caption)
            Text(text).font(.caption)
                .foregroundColor(met ? .primary : .secondary)
        }
    }
}

// MARK: - Local shake
private extension View {
    func shakeLocal(trigger: CGFloat) -> some View {
        modifier(LocalShakeModifier(animatableData: trigger))
    }
}
private struct LocalShakeModifier: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit   = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)), y: 0
        ))
    }
}

// MARK: - SocialButton
struct SocialButton: View {
    let icon: String; let label: String; let bg: Color; let fg: Color
    var body: some View {
        Button {} label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.subheadline).bold()
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(bg)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 0.5))
        }
    }
}

#Preview {
    LoginView(mode: .signUp).environmentObject(AuthViewModel())
}
