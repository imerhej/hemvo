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
        print("[Push] APNs registration failed: \(error)")
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
            if authVM.isCheckingSession {
                // Supabase session check in flight — show splash to prevent
                // the router from evaluating household/paywall state too early.
                SplashView()

            } else if !authVM.isLoggedIn {
                OnboardingView()

            } else if authVM.trialExpired {
                PaywallView()

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
        .animation(.easeInOut, value: householdService.household == nil)
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
