// LoginView.swift
// Hemvo
//
// Updated for Supabase backend:
// • authVM.login(email:password:) — email only, no username login
// • authVM.signUp(name:email:password:) — username field removed (Supabase handles identity)
// • sendResetLink() uses AuthService.shared.sendPasswordReset(to:) — no local token/EmailService
// • EmailValidator.shared singleton used directly
// • emailValidator.quickCheck() no longer takes isSignUp parameter

internal import SwiftUI
internal import LocalAuthentication
internal import Combine
internal import AuthenticationServices

enum AuthMode { case login, signUp }

struct LoginView: View {

    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var mode: AuthMode
    @State private var name            = ""
    @State private var username        = ""
    @State private var emailOrUsername = ""
    @State private var password        = ""
    @State private var confirmPass     = ""
    @State private var showPassword    = false
    @State private var showConfirmPass = false
    @State private var shakeTrigger: CGFloat = 0
    @State private var appearAnim      = false
    @State private var signUpSuccess   = false
    @State private var signUpEmail     = ""

    // MARK: - Focus State
    private enum Field: Hashable {
        case name, username, emailOrUsername, password, confirmPass
        case verificationCode
        case resetEmail
    }
    @FocusState private var focus: Field?

    // Per-field focus booleans wired to LoginField / PasswordLoginField externalFocus bindings.
    @State private var focusName            = false
    @State private var focusUsername        = false
    @State private var focusEmailOrUsername = false
    @State private var focusPassword        = false
    @State private var focusConfirmPass     = false

    private func setFocus(_ field: Field?) {
        focusName            = false
        focusUsername        = false
        focusEmailOrUsername = false
        focusPassword        = false
        focusConfirmPass     = false
        focus = field
        switch field {
        case .name:            focusName            = true
        case .username:        focusUsername        = true
        case .emailOrUsername: focusEmailOrUsername = true
        case .password:        focusPassword        = true
        case .confirmPass:     focusConfirmPass     = true
        default: break
        }
    }

    @StateObject private var emailValidator = EmailValidator.shared

    // Email verification flow
    @State private var showVerification  = false
    @State private var verificationCode  = ""
    @State private var enteredCode       = ""
    @State private var verifyError       = false
    @State private var isSendingCode     = false
    @State private var sendCodeError     = false

    // Forgot password flow
    @State private var showForgotPassword = false
    @State private var resetEmail         = ""
    @State private var resetError         = ""
    @State private var resetSuccess       = false
    @State private var isSendingReset     = false

    init(mode: AuthMode) { _mode = State(initialValue: mode) }

    var isSignUp: Bool { mode == .signUp }

    // MARK: - Validation
    var isUsernameValid: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "_"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    var isFormValid: Bool {
        if isSignUp {
            switch emailValidator.result {
            case .invalid, .alreadyRegistered: return false
            default: break
            }
            return !name.isEmpty
                && !emailOrUsername.isEmpty
                && isUsernameValid
                && password.count >= 8
                && password.contains(where: \.isUppercase)
                && password.contains(where: \.isNumber)
                && password == confirmPass
        }
        return !emailOrUsername.isEmpty && !password.isEmpty
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

    private var resetButtonDisabled: Bool {
        switch emailValidator.quickCheck(resetEmail) {
        case .valid: return false
        default:     return true
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            LinearGradient(
                colors: modeGradient,
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: mode)

            Circle().fill(Color.white.opacity(0.05)).frame(width: 320).offset(x: 160, y: -220)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 180).offset(x: -100, y: 320)

            VStack(spacing: 0) {
                topBar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        brandHeader.padding(.top, 8)

                        if signUpSuccess {
                            signUpSuccessCard
                                .padding(.horizontal, 20)
                                .transition(.opacity.combined(with: .scale))
                        } else {
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
                        }

                        if !signUpSuccess {
                            if !isSignUp && authVM.isBiometricEnabled {
                                faceIDButton.padding(.horizontal, 20)
                            }

                            toggleMode

                            HStack {
                                Rectangle().fill(Color.white.opacity(0.25)).frame(height: 0.5)
                                Text("or")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 10)
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
                        }
                        Spacer(minLength: 40)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5).delay(0.1)) { appearAnim = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                setFocus(isSignUp ? .name : .emailOrUsername)
            }
        }
        .onChange(of: mode) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                setFocus(isSignUp ? .name : .emailOrUsername)
            }
        }
        .sheet(isPresented: $showVerification) {
            emailVerificationSheet
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        focus = .verificationCode
                    }
                }
        }
        .sheet(isPresented: $showForgotPassword) {
            forgotPasswordSheet
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        focus = .resetEmail
                    }
                }
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
                Text(isSignUp ? "Start your 7-day free trial today" : "Sign in to Hemvo")
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
                    LoginField(
                        label: "Full Name", text: $name,
                        icon: "person.fill", accent: modeAccent,
                        keyboard: .default, autocap: .words,
                        submitLabelType: .next,
                        onSubmitAction: { setFocus(.username) },
                        externalFocus: $focusName
                    )
                    fieldDivider
                    LoginField(
                        label:   "Username",
                        text:    $username,
                        icon:    "at",
                        accent:  modeAccent,
                        keyboard: .asciiCapable,
                        autocap: .never,
                        submitLabelType: .next,
                        onSubmitAction: { setFocus(.emailOrUsername) },
                        externalFocus: $focusUsername
                    )
                    // Username hint
                    Group {
                        if !username.isEmpty {
                            if isUsernameValid {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Username looks good")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(Color(hex: "#3D7A52")!)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Min 3 characters, letters, numbers and _ only")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.red)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: username)
                    fieldDivider
                }

                LoginField(
                    label:    isSignUp ? "Email Address" : "Email or Username",
                    text:     $emailOrUsername,
                    icon:     isSignUp ? "envelope.fill" : "person.circle.fill",
                    accent:   modeAccent,
                    keyboard: isSignUp ? .emailAddress : .default,
                    autocap:  .never,
                    submitLabelType: .next,
                    onSubmitAction: { setFocus(.password) },
                    externalFocus: $focusEmailOrUsername
                )
                .onChange(of: emailOrUsername) { _, new in
                    if isSignUp {
                        emailValidator.validate(new, isSignUp: true)
                    }
                }

                // Email validation feedback — sign-up only
                if isSignUp {
                    Group {
                        switch emailValidator.result {
                        case .invalid(let msg):
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(msg).font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        case .alreadyRegistered(let existingEmail):
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color(hex: "#2196F3")!)
                                    Text("Account already exists")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(Color(hex: "#1A1208")!)
                                }
                                Text("\(existingEmail) is already registered.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(hex: "#7A6A55")!)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        mode = .login
                                        authVM.errorMessage = nil
                                        name = ""; confirmPass = ""
                                        showPassword = false; showConfirmPass = false
                                        emailValidator.reset()
                                        emailOrUsername = existingEmail
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 13, weight: .bold))
                                        Text("Sign in instead")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Color(hex: "#2196F3")!)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "#2196F3")!.opacity(0.07))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "#2196F3")!.opacity(0.25), lineWidth: 1))
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))

                        case .suggestion(let suggestion):
                            Button {
                                let corrected = suggestion
                                    .replacingOccurrences(of: "Did you mean ", with: "")
                                    .replacingOccurrences(of: "?", with: "")
                                    .trimmingCharacters(in: .whitespaces)
                                emailOrUsername = corrected
                                emailValidator.validate(corrected, isSignUp: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(suggestion + " Tap to fix.")
                                        .font(.system(size: 12, weight: .semibold))
                                        .multilineTextAlignment(.leading)
                                }
                                .foregroundColor(Color(hex: "#E67E22")!)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        case .checking:
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7).tint(modeAccent)
                                Text("Verifying email…")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)

                        case .valid:
                            if !emailOrUsername.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Email looks good")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(Color(hex: "#3D7A52")!)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: emailValidator.result)
                }

                fieldDivider

                PasswordLoginField(
                    label: "Password",
                    text: $password,
                    showText: $showPassword,
                    accent: modeAccent,
                    submitLabelType: isSignUp ? .next : .go,
                    onSubmitAction: {
                        if isSignUp { setFocus(.confirmPass) }
                        else { submit() }
                    },
                    externalFocus: $focusPassword
                )

                if isSignUp {
                    fieldDivider
                    PasswordLoginField(
                        label:         "Confirm Password",
                        text:          $confirmPass,
                        showText:      $showConfirmPass,
                        accent:        modeAccent,
                        trailing:      password == confirmPass && !confirmPass.isEmpty
                            ? "checkmark.circle.fill" : nil,
                        trailingColor: .homeBaseGreen,
                        submitLabelType: .done,
                        onSubmitAction: { setFocus(nil); submit() },
                        externalFocus: $focusConfirmPass
                    )
                    fieldDivider
                    VStack(alignment: .leading, spacing: 8) {
                        PasswordHint(text: "At least 8 characters", met: password.count >= 8)
                        PasswordHint(text: "One uppercase letter",  met: password.contains(where: \.isUppercase))
                        PasswordHint(text: "One number",            met: password.contains(where: \.isNumber))
                        PasswordHint(text: "Passwords match",       met: password == confirmPass && !confirmPass.isEmpty)
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
                        resetEmail   = emailOrUsername.contains("@") ? emailOrUsername : ""
                        resetError   = ""
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
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(modeAccent.opacity(0.3), lineWidth: 1.5))
            .opacity(isFormValid ? 1 : 0.6)
        }
        .disabled(!isFormValid || authVM.isLoading)
        .animation(.easeInOut(duration: 0.2), value: isFormValid)
    }

    // MARK: - Face ID Button
    private var faceIDButton: some View {
        Button { authVM.loginWithBiometrics() } label: {
            HStack(spacing: 10) {
                Image(systemName: authVM.biometricIcon)
                    .font(.system(size: 20, weight: .semibold))
                Text("Sign in with \(authVM.biometricLabel)")
                    .font(.headline).bold()
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.white.opacity(0.18))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.35), lineWidth: 1.5))
        }
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
                    signUpSuccess = false
                    emailOrUsername = ""
                    emailValidator.reset()
                    name = ""; username = ""; confirmPass = ""
                    showPassword = false; showConfirmPass = false
                }
            }
            .font(.subheadline).bold().foregroundColor(.white).underline()
        }
    }

    // MARK: - Social Buttons
    private var socialButtons: some View {
        VStack(spacing: 10) {
            Button { authVM.loginWithApple() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Continue with Apple").font(.subheadline).bold()
                }
                .foregroundColor(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.label))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.systemGray4), lineWidth: 0.5))
            }

            Button { authVM.loginWithGoogle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Continue with Google").font(.subheadline).bold()
                }
                .foregroundColor(Color(.label))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.systemGray4), lineWidth: 0.5))
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
                                Text("Sending code to \(emailOrUsername)…")
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                        } else if sendCodeError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Email send failed. Check console for code (dev).")
                                    .font(.subheadline).foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        } else {
                            Text("We sent a 6-digit code to\n\(emailOrUsername)")
                                .font(.subheadline).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

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
                                    .stroke(verifyError ? Color.red : modeAccent.opacity(0.4),
                                            lineWidth: 2)
                            )
                            .focused($focus, equals: .verificationCode)
                            .submitLabel(.done)
                            .onSubmit { if enteredCode.count == 6 { verifyCode() } }
                            .onChange(of: enteredCode) { _, new in
                                let filtered = new.filter { $0.isNumber }
                                enteredCode  = filtered.count > 6
                                    ? String(filtered.prefix(6)) : filtered
                                verifyError  = false
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

                    Button { verifyCode() } label: {
                        Text("Verify & Continue")
                            .font(.headline).bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(enteredCode.count == 6 ? modeAccent : Color.gray.opacity(0.4))
                            .cornerRadius(14)
                    }
                    .disabled(enteredCode.count < 6 || isSendingCode)
                    .padding(.horizontal, 24)

                    Button { sendVerificationCode() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                            Text("Resend Code")
                        }
                        .font(.subheadline).foregroundColor(modeAccent)
                    }
                    .disabled(isSendingCode)

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
    }

    // MARK: - Forgot Password Sheet
    private var forgotPasswordSheet: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#F4F6FB")!.ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer().frame(height: 8)

                    ZStack {
                        Circle().fill(modeAccent.opacity(0.1)).frame(width: 100, height: 100)
                        Image(systemName: resetSuccess
                              ? "checkmark.circle.fill"
                              : "envelope.badge.fill")
                            .font(.system(size: 44))
                            .foregroundColor(resetSuccess ? .green : modeAccent)
                    }
                    .animation(.spring(response: 0.4), value: resetSuccess)

                    if resetSuccess {
                        VStack(spacing: 10) {
                            Text("Check Your Email")
                                .font(.system(size: 24, weight: .black))
                            Text("We sent a password reset link to\n\(resetEmail)")
                                .font(.subheadline).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Text("Tap the link in your email to set a new password. Check your spam folder if you don't see it.")
                                .font(.caption).foregroundColor(.secondary)
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
                        VStack(spacing: 10) {
                            Text("Forgot Password?")
                                .font(.system(size: 24, weight: .black))
                            Text("Enter your email and we'll send you\na link to reset your password.")
                                .font(.subheadline).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL ADDRESS")
                                .font(.system(size: 9, weight: .heavy)).kerning(1.3)
                                .foregroundColor(.secondary).padding(.leading, 2)
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(modeAccent).frame(width: 20)
                                TextField("your@email.com", text: $resetEmail)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 16, weight: .semibold))
                                    .focused($focus, equals: .resetEmail)
                                    .submitLabel(.done)
                                    .onSubmit { if !resetButtonDisabled { sendResetLink() } }
                            }
                            .padding(16)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(modeAccent.opacity(0.35), lineWidth: 1.5))
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
                            ZStack {
                                if isSendingReset {
                                    ProgressView().tint(.white)
                                } else {
                                    HStack(spacing: 10) {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 15))
                                        Text("Send Reset Link")
                                            .font(.system(size: 16, weight: .bold))
                                    }
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(resetButtonDisabled ? Color.gray.opacity(0.35) : modeAccent)
                            .cornerRadius(14)
                            .animation(.easeInOut(duration: 0.15), value: resetButtonDisabled)
                        }
                        .disabled(resetButtonDisabled || isSendingReset)
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

    // MARK: - Reset Link
    // Supabase sends the reset email and handles token generation server-side.
    // No PasswordResetService or EmailService needed.
    private func sendResetLink() {
        let trimmed = resetEmail.lowercased().trimmingCharacters(in: .whitespaces)
        resetError    = ""
        isSendingReset = true

        Task {
            do {
                try await AuthService.shared.sendPasswordReset(to: trimmed)
                await MainActor.run {
                    isSendingReset = false
                    withAnimation(.spring()) { resetSuccess = true }
                }
            } catch {
                await MainActor.run {
                    isSendingReset = false
                    resetError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Submit
    // Supabase handles email verification automatically after signUp().
    // No verification sheet or code needed — Supabase emails the user a
    // confirmation link. The sheet state vars are kept to avoid breaking
    // any remaining references but are never triggered.
    private func submit() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )

        if isSignUp {
            let check = emailValidator.quickCheck(emailOrUsername)
            if case .invalid(let msg) = check {
                authVM.errorMessage = msg
                withAnimation { shakeTrigger += 1 }
                return
            }
            if case .alreadyRegistered = check {
                authVM.errorMessage = "An account with this email already exists. Please sign in."
                withAnimation { shakeTrigger += 1 }
                return
            }
            Task {
                let email = emailOrUsername
                let success = await authVM.signUp(
                    name:     name,
                    email:    email,
                    username: username.lowercased().trimmingCharacters(in: .whitespaces),
                    password: password
                )
                if success {
                    signUpEmail     = email
                    name            = ""
                    username        = ""
                    emailOrUsername = ""
                    password        = ""
                    confirmPass     = ""
                    showPassword    = false
                    showConfirmPass = false
                    emailValidator.reset()
                    withAnimation(.spring(response: 0.4)) { signUpSuccess = true }
                } else {
                    withAnimation { shakeTrigger += 1 }
                }
            }
        } else {
            Task {
                await authVM.login(emailOrUsername: emailOrUsername, password: password)
                if authVM.errorMessage != nil {
                    withAnimation { shakeTrigger += 1 }
                }
            }
        }
    }

    // Kept as stubs — no longer called, Supabase handles verification
    private func sendVerificationCode() { }
    private func verifyCode() {
        guard enteredCode == verificationCode else {
            withAnimation { verifyError = true }
            return
        }
        showVerification = false
    }

    // MARK: - Sign-Up Success Card
    private var signUpSuccessCard: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Color.white.opacity(0.15)).frame(width: 90, height: 90)
                Circle().fill(Color.white.opacity(0.25)).frame(width: 68, height: 68)
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.white)
            }

            VStack(spacing: 10) {
                Text("Check Your Email")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                Text("We sent a confirmation link to")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Text(signUpEmail)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                Text("Tap the link in your email to activate your account, then come back to sign in.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    signUpSuccess   = false
                    mode            = .login
                    emailOrUsername = signUpEmail
                    authVM.errorMessage = nil
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Go to Sign In")
                        .font(.headline.bold())
                    Image(systemName: "arrow.right.circle.fill")
                }
                .foregroundColor(modeAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            }
        }
        .padding(28)
        .background(Color.white.opacity(0.12))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - PasswordLoginField
struct PasswordLoginField: View {
    let label:         String
    @Binding var text:     String
    @Binding var showText: Bool
    let accent:        Color
    var trailing:      String? = nil
    var trailingColor: Color   = .homeBaseGreen
    var submitLabelType: SubmitLabel = .done
    var onSubmitAction: (() -> Void)? = nil
    /// Set to `true` externally (via DispatchQueue.main.async) to programmatically focus this field.
    var externalFocus: Binding<Bool>? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 15))
                .foregroundColor(focused ? accent : Color(.systemGray3))
                .frame(width: 20).padding(.leading, 16)
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
            .submitLabel(submitLabelType)
            .onSubmit { onSubmitAction?() }
            .font(.subheadline)
            .padding(.vertical, 16)
            // Sync internal focus state to/from the external binding.
            .onChange(of: focused) { _, isFocused in externalFocus?.wrappedValue = isFocused }
            .onChange(of: externalFocus?.wrappedValue ?? false) { _, shouldFocus in
                if shouldFocus { focused = true }
            }

            if let t = trailing {
                Image(systemName: t)
                    .foregroundColor(trailingColor)
                    .font(.subheadline).padding(.trailing, 4)
                    .transition(.scale.combined(with: .opacity))
            }
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

// MARK: - LoginField
struct LoginField: View {
    let label:         String
    @Binding var text: String
    let icon:          String
    let accent:        Color
    var keyboard:      UIKeyboardType              = .default
    var autocap:       TextInputAutocapitalization = .never
    var isSecure:      Bool                        = false
    var trailingIcon:  String?                     = nil
    var trailingColor: Color                       = .homeBaseGreen
    var submitLabelType: SubmitLabel               = .next
    var onSubmitAction: (() -> Void)?              = nil
    /// When bound to a Bool, the component mirrors its internal focus state to this binding.
    /// Set to `true` externally (via DispatchQueue.main.async) to programmatically focus this field.
    var externalFocus: Binding<Bool>?              = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(focused ? accent : Color(.systemGray3))
                .frame(width: 20).padding(.leading, 16)
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
            .submitLabel(submitLabelType)
            .onSubmit { onSubmitAction?() }
            .font(.subheadline)
            .padding(.vertical, 16)
            // Sync internal focus state to/from the external binding.
            .onChange(of: focused) { _, isFocused in externalFocus?.wrappedValue = isFocused }
            .onChange(of: externalFocus?.wrappedValue ?? false) { _, shouldFocus in
                if shouldFocus { focused = true }
            }

            if let trailing = trailingIcon {
                Image(systemName: trailing)
                    .foregroundColor(trailingColor)
                    .font(.subheadline).padding(.trailing, 14)
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

// MARK: - Shake modifier
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
            translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0
        ))
    }
}

#Preview {
    LoginView(mode: .signUp).environmentObject(AuthViewModel())
}
