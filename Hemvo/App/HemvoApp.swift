//  HemvoApp.swift
//  Hemvo
//  App entry point. Schedules tomorrow reminders for meals, events, and
//  maintenance on every launch. Badge count is always cleared to zero.
//  Household sharing: after login, routes to HouseholdSetupView until the
//  user has created or joined a household.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import Combine     // ← required: ObservableObject lives in Combine
internal import UIKit
internal import Supabase
internal import Auth
internal import OSLog

// MARK: - Jailbreak detection
// Checks common jailbreak indicators at launch. On a compromised device the app
// shows a blocking warning so the user knows their environment is untrusted.
// This is defense-in-depth — a sophisticated attacker can bypass these checks —
// but it raises the bar against casual exploitation of sensitive Keychain data.
func isDeviceJailbroken() -> Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    // 1. Known jailbreak filesystem artifacts
    let jailbreakPaths: [String] = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/usr/sbin/sshd",
        "/usr/bin/ssh",
        "/etc/apt",
        "/private/var/lib/apt/",
        "/bin/bash",
        "/bin/sh",
        "/private/var/stash",
    ]
    if let hit = jailbreakPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
        Logger.security.error("Jailbreak indicator: filesystem artifact \(hit, privacy: .public)")
        return true
    }

    // 2. Sandbox write probe — only succeeds on jailbroken devices.
    let probeFile = "/private/hemvo_jb_probe_\(Int.random(in: 1_000_000...9_999_999))"
    do {
        try "probe".write(toFile: probeFile, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(atPath: probeFile)
        Logger.security.error("Jailbreak indicator: sandbox escape — wrote outside the container")
        return true
    } catch { }

    // 3. Injected dynamic libraries — Substrate tweaks, Cycript, SSL kill switches,
    //    and similar tools load themselves into every process on jailbroken devices.
    let suspiciousDylibs = [
        "MobileSubstrate", "SubstrateLoader", "cynject",
        "libcycript", "rocketbootstrap", "SSLKillSwitch",
        "FLEXLoader", "libhooker", "substitute",
    ]
    for i in 0..<_dyld_image_count() {
        if let rawName = _dyld_get_image_name(i) {
            let imageName = String(cString: rawName)
            if suspiciousDylibs.contains(where: { imageName.localizedCaseInsensitiveContains($0) }) {
                Logger.security.error("Jailbreak indicator: loaded dylib \(imageName, privacy: .public)")
                return true
            }
        }
    }

    // 4. Protected system directories replaced by symlinks — a common jailbreak
    //    side effect where read-only partitions are re-mounted read-write and key
    //    directories are redirected via symlinks.
    let protectedPaths = [
        "/Applications",
        "/Library/Ringtones",
        "/Library/Wallpaper",
        "/usr/include",
        "/usr/libexec",
        "/usr/share",
    ]
    for path in protectedPaths {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil {
            Logger.security.error("Jailbreak indicator: \(path, privacy: .public) is a symlink")
            return true
        }
    }

    // 5. DYLD_INSERT_LIBRARIES present — indicates the dynamic linker injected a
    //    library into this process before main() ran. Xcode and Instruments use
    //    the same mechanism to load Apple's own diagnostic libraries: running on
    //    a device with the Main Thread Checker (on by default in the Debug
    //    scheme), a sanitizer, or malloc guard enabled sets this variable on
    //    every launch. Treating its mere presence as an injection flags every
    //    development build on real hardware, so only libraries outside Apple's
    //    known diagnostic set count.
    if let rawInserted = getenv("DYLD_INSERT_LIBRARIES") {
        let appleDiagnosticLibs: Set<String> = [
            "libMainThreadChecker.dylib",
            "libViewDebuggerSupport.dylib",
            "libBacktraceRecording.dylib",
            "libRPAC.dylib",
            "libgmalloc.dylib",
        ]
        let injected = String(cString: rawInserted)
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).lastPathComponent }

        let unexpected = injected.filter { lib in
            !appleDiagnosticLibs.contains(lib) && !lib.hasPrefix("libclang_rt.")
        }
        if !unexpected.isEmpty {
            Logger.security.error("Jailbreak indicator: injected \(unexpected.joined(separator: ", "), privacy: .public)")
            return true
        }
    }

    return false
    #endif
}

// MARK: - APNs delegate
// Receives the device token once iOS registers with Apple's push servers.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationService.shared.registerToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.push.error("APNs registration failed: \(error.localizedDescription)")
    }
}

// MARK: - Singleton holders
//
// @StateObject requires an ObservableObject whose initialiser it controls.
// Both HouseholdService and StoreKitService have private/inaccessible inits
// (singletons), so we wrap each in a thin holder.

private final class HouseholdServiceHolder: ObservableObject {
    let service = HouseholdService.shared
}

private final class StoreKitServiceHolder: ObservableObject {
    let service = StoreKitService.shared
}

// MARK: - App Entry Point

@main
struct HemvoApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        UserDefaultsMigration.runIfNeeded()
        UIScrollView.appearance().keyboardDismissMode = .interactive
    }

    @StateObject private var authVM      = AuthViewModel()
    @StateObject private var hsHolder    = HouseholdServiceHolder()
    @StateObject private var skHolder    = StoreKitServiceHolder()
    @StateObject private var prefs       = UserPreferences.shared
    let persistence                      = PersistenceService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authVM)
                .environmentObject(hsHolder.service)   // HouseholdService
                .environmentObject(skHolder.service)   // StoreKitService
                .environmentObject(prefs)              // UserPreferences
                .environment(\.managedObjectContext,
                             persistence.container.viewContext)
                .onOpenURL { url in
                    // Only handle hemvo://reset-password URLs. Establishing the
                    // Supabase recovery session first means a malicious app
                    // spoofing the URL scheme cannot trigger the reset UI with a
                    // forged token — the form only appears once the server
                    // accepts the recovery token.
                    guard url.scheme == "hemvo", url.host == "reset-password" else { return }
                    // Must be set BEFORE session(from:) runs: the .signedIn
                    // event it emits would otherwise start the full post-login
                    // pipeline underneath ResetPasswordView (see AuthViewModel.
                    // isHandlingPasswordRecovery).
                    authVM.isHandlingPasswordRecovery = true
                    Task {
                        do {
                            try await supabase.auth.session(from: url)
                            await MainActor.run { authVM.showResetPassword = true }
                        } catch {
                            await MainActor.run { authVM.isHandlingPasswordRecovery = false }
                            Logger.deepLink.error("session(from:) failed: \(error.localizedDescription)")
                        }
                    }
                }
                .task {
                    // 1. Request local + remote notification permission
                    let granted = await NotificationService.shared.requestAuthorization()
                    if granted {
                        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
                    }

                    // 2. Always clear badge on launch
                    NotificationService.shared.clearBadge()

                    // 3. Schedule tomorrow reminders
                    await scheduleTomorrowReminders()
                }
                // Re-clear badge and refresh reminders on each foreground entry.
                // Use onReceive (not onChange of scenePhase) to stay compatible
                // with iOS 17 and avoid the 2-argument closure compiler error.
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification)
                ) { _ in
                    NotificationService.shared.clearBadge()
                    PushNotificationService.shared.refreshToken()
                    Task { await scheduleTomorrowReminders() }
                    Task { await authVM.refreshSubscriptionStatus() }
                }
        }
    }

    // MARK: - Schedule all tomorrow reminders

    @MainActor
    private func scheduleTomorrowReminders() async {
        let svc   = NotificationService.shared
        let prefs = UserPreferences.shared

        // Meals
        let meals = loadMeals()
        if prefs.notifMeals {
            svc.scheduleMealReminders(meals: meals)
        } else {
            svc.cancelMealReminders()
        }

        // Calendar events
        let events = loadEvents()
        if prefs.notifSchedule {
            svc.scheduleEventReminders(for: events)
        } else {
            for event in events { svc.cancelEventReminders(for: event.id) }
        }

        // Maintenance
        let maintItems = loadMaintenanceItems()
        if prefs.notifMaintenance {
            svc.scheduleMaintenanceReminders(for: maintItems)
        } else {
            for item in maintItems { svc.cancelMaintenanceReminder(for: item.id) }
        }

        // Bills
        if prefs.notifBills {
            svc.rescheduleAllBills(from: loadExpenses())
        } else {
            svc.cancelAllBillReminders()
        }
    }

    // MARK: - Lightweight data loaders
    // Read directly from UserDefaults using the same keys each ViewModel uses.
    // This avoids instantiating heavy ViewModels at the app level.

    private func loadMeals() -> [Meal] {
        guard let data  = UserDefaults.standard.data(forKey: "hemvo_meals"),
              let items = try? JSONDecoder().decode([Meal].self, from: data)
        else { return [] }
        return items
    }

    private func loadEvents() -> [CalendarEvent] {
        guard let data  = UserDefaults.standard.data(forKey: "hemvo_events"),
              let items = try? JSONDecoder().decode([CalendarEvent].self, from: data)
        else { return [] }
        return items.filter { $0.date >= Date() }
    }

    private func loadMaintenanceItems() -> [MaintenanceItem] {
        guard let data  = UserDefaults.standard.data(forKey: "hemvo_maintenanceItems"),
              let items = try? JSONDecoder().decode([MaintenanceItem].self, from: data)
        else { return [] }
        return items
    }

    private func loadExpenses() -> [Expense] {
        guard let data  = UserDefaults.standard.data(forKey: "hemvo_expenses"),
              let items = try? JSONDecoder().decode([Expense].self, from: data)
        else { return [] }
        return items
    }
}

// MARK: - Root routing view
//
// Routing order (top = highest priority):
//   1. Not logged in                      → OnboardingView
//   2. Trial expired, no paid sub         → PaywallView
//   3. Logged in, no household yet        → HouseholdSetupView
//   4. Logged in + valid + household      → ContentView

private struct RootView: View {
    @EnvironmentObject var authVM:           AuthViewModel
    @EnvironmentObject var householdService: HouseholdService
    var body: some View {
        Group {
            if isDeviceJailbroken() {
                JailbreakWarningView()
            } else if authVM.isCheckingSession || authVM.isResolvingAccess {
                // Show splash while the initial session check OR post-login
                // subscription refresh is in flight, so trialExpired / paywall
                // state is never evaluated before subscription status is known.
                SplashView()

            } else if !authVM.isLoggedIn {
                OnboardingView()

            } else if authVM.trialExpired {
                PaywallView()

            } else if authVM.ownerSubscriptionLapsed {
                OwnerLapsedView()
                    .environmentObject(authVM)
                    .environmentObject(householdService)

            } else if householdService.household == nil {
                HouseholdSetupView()
                    .environmentObject(authVM)
                    .environmentObject(householdService)

            } else {
                ContentView()
                    .environmentObject(householdService)
            }
        }
        .animation(.easeInOut, value: authVM.isCheckingSession)
        .animation(.easeInOut, value: authVM.isLoggedIn)
        .animation(.easeInOut, value: authVM.trialExpired)
        .animation(.easeInOut, value: authVM.ownerSubscriptionLapsed)
        .animation(.easeInOut, value: householdService.household == nil)
        .fullScreenCover(
            isPresented: Binding(
                get: { authVM.showResetPassword },
                set: { authVM.showResetPassword = $0 }
            )
        ) {
            ResetPasswordView(onComplete: {
                authVM.showResetPassword = false
                // Discard the recovery session; the user signs back in with
                // the new password. Clear the recovery flag only after the
                // sign-out so the .signedOut event can't be misread as a
                // user-initiated logout mid-flow.
                Task {
                    try? await supabase.auth.signOut()
                    await MainActor.run { authVM.isHandlingPasswordRecovery = false }
                }
                authVM.signOut()
            })
        }
    }
}

// MARK: - Jailbreak warning — blocks all app functionality on compromised devices
private struct JailbreakWarningView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.red)
                Text("Untrusted Device")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(.white)
                Text("Hemvo has detected that this device may be jailbroken. The app cannot run safely in this environment.\n\nYour household data and account credentials are protected.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

// MARK: - Splash screen shown while the session check is in flight
private struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#1B5E34") ?? .green, Color(hex: "#4CAF74") ?? .green],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.12 : 1.0)
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 90, height: 90)
                    Image(systemName: "house.circle.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.white)
                }
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                           value: pulse)
                .onAppear { pulse = true }

                Text("Hemvo")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.white)
            }
        }
    }
}
