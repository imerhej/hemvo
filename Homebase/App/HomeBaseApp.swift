//  HomeBaseApp.swift
//  HomeBase
//  App entry point. Handles deep links including password reset.

internal import SwiftUI
internal import StoreKit
internal import CoreData

@main
struct HomeBaseApp: App {

    @StateObject private var authVM   = AuthViewModel()
    @StateObject private var storeKit = StoreKitService.shared
    let persistence                   = PersistenceService.shared

    // Deep link state
    @State private var resetToken: String? = nil

    var body: some Scene {
        WindowGroup {
            RootView(resetToken: $resetToken)
                .environmentObject(authVM)
                .environmentObject(storeKit)
                .environment(\.managedObjectContext,
                             persistence.container.viewContext)
                .task {
                    let granted = await NotificationService.shared.requestAuthorization()
                    print("HomeBase: notification permission granted = \(granted)")
                }
                // Handle universal links and custom URL schemes
                .onOpenURL { url in
                    if let token = PasswordResetService.shared.tokenFromURL(url) {
                        resetToken = token
                    }
                }
                // Present ResetPasswordView as a full-screen cover
                .fullScreenCover(item: Binding(
                    get: { resetToken.map { ResetTokenWrapper(token: $0) } },
                    set: { if $0 == nil { resetToken = nil } }
                )) { wrapper in
                    ResetPasswordView(token: wrapper.token) {
                        resetToken = nil
                    }
                }
        }
    }
}

// Identifiable wrapper so fullScreenCover(item:) works
private struct ResetTokenWrapper: Identifiable {
    let id    = UUID()
    let token: String
}

// MARK: - Root routing view
private struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var resetToken: String?

    var body: some View {
        Group {
            if !authVM.isLoggedIn {
                OnboardingView()
            } else if !authVM.isSubscriptionActive {
                PaywallView()
            } else {
                ContentView()
            }
        }
        .animation(.easeInOut, value: authVM.isLoggedIn)
        .animation(.easeInOut, value: authVM.isSubscriptionActive)
        .task {
            await authVM.refreshSubscriptionStatus()
        }
    }
}
