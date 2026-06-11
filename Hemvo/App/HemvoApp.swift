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
    let paths: [String] = [
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
    if paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
        return true
    }
    // Attempt a write outside the sandbox — only succeeds on jailbroken devices.
    let probeFile = "/private/hemvo_jb_probe_\(Int.random(in: 1_000_000...9_999_999))"
    do {
        try "probe".write(toFile: probeFile, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(atPath: probeFile)
        return true
    } catch { }
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
                    // Show the reset form immediately so the user isn't left
                    // on the sign-in page while session(from:) runs async.
                    // session(from:) then establishes the recovery session in
                    // the background — well before the user finishes typing.
                    if url.host == "reset-password" {
                        authVM.showResetPassword = true
                    }
                    Task {
                        do {
                            try await supabase.auth.session(from: url)
                        } catch {
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
        guard let data  = UserDefaults.standard.data(forKey: "hb_meals"),
              let items = try? JSONDecoder().decode([Meal].self, from: data)
        else { return [] }
        return items
    }

    private func loadEvents() -> [CalendarEvent] {
        guard let data  = UserDefaults.standard.data(forKey: "hb_events"),
              let items = try? JSONDecoder().decode([CalendarEvent].self, from: data)
        else { return [] }
        return items.filter { $0.date >= Date() }
    }

    private func loadMaintenanceItems() -> [MaintenanceItem] {
        guard let data  = UserDefaults.standard.data(forKey: "hb_maintenanceItems"),
              let items = try? JSONDecoder().decode([MaintenanceItem].self, from: data)
        else { return [] }
        return items
    }

    private func loadExpenses() -> [Expense] {
        guard let data  = UserDefaults.standard.data(forKey: "hb_expenses"),
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
                Task { try? await supabase.auth.signOut() }
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
