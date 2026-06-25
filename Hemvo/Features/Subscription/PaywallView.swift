//  PaywallView.swift
//  Hemvo
//  Trial-expired / upgrade screen with monthly and annual subscription options.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

struct PaywallView: View {

    @EnvironmentObject var authVM:   AuthViewModel
    @EnvironmentObject var storeKit: StoreKitService
    @Environment(\.dismiss) var dismiss

    @AppStorage("hemvo_avatarColor") private var avatarColor: String = "#4CAF74"

    @State private var selectedPlan  = StoreIDs.annual
    @State private var isPurchasing  = false
    @State private var isRestoring   = false
    @State private var errorMessage: String?
    @State private var showSuccess   = false
    @State private var animateBadge  = false

    var accentColor: Color { Color(hex: avatarColor) ?? .homeBaseGreen }

    private let features: [(icon: String, color: Color, title: String, desc: String)] = [
        ("fork.knife.circle.fill",             .orange,          "Meal Planning",       "Weekly plans & auto grocery lists"),
        ("dollarsign.circle.fill",             .blue,            "Budget Tracking",     "Expenses, limits & bill reminders"),
        ("calendar.circle.fill",              .purple,          "Family Schedule",     "Shared calendar & task delegation"),
        ("wrench.and.screwdriver",            .red,             "Home Maintenance",    "Chore tracker & seasonal checklists"),
        ("icloud.circle.fill",               .teal,            "iCloud Sync",         "Access your data on all devices"),
        ("bell.badge.circle.fill",           .orange,          "Smart Reminders",     "Never miss a bill or chore again"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.homeBaseBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection
                        VStack(spacing: 24) {
                            featureGrid
                            planSelector
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text(error).font(.caption).foregroundColor(.red)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ctaSection
                            footerLinks
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 48)
                    }
                }

                if showSuccess { successOverlay }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(accentColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.subheadline).bold()
                        .foregroundColor(.red)
                }
            }
            .onAppear { Task { await storeKit.loadProducts() } }
        }
    }

    // MARK: - Hero
    private var heroSection: some View {
        ZStack {
            accentColor.ignoresSafeArea(edges: .top)

            Circle().fill(Color.white.opacity(0.06)).frame(width: 220).offset(x: 130, y: -60)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 150).offset(x: -90, y: 70)

            VStack(spacing: 16) {
                // Animated badge
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .scaleEffect(animateBadge ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                                   value: animateBadge)

                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 78, height: 78)

                    Image(systemName: "house.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    if authVM.trialDaysRemaining > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill").font(.caption)
                            Text("\(authVM.trialDaysRemaining) days left in trial")
                                .font(.caption).bold()
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(20)
                    }

                    Text("Unlock Hemvo")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    Text("Everything you need to\nrun your home in one place.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 36)
        }
        .onAppear { animateBadge = true }
    }

    // MARK: - Feature Grid
    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Everything included")
                .font(.headline)
                .padding(.bottom, 2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(features, id: \.title) { f in
                    HStack(spacing: 10) {
                        Image(systemName: f.icon)
                            .font(.system(size: 22))
                            .foregroundColor(f.color)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(.caption).bold()
                            Text(f.desc).font(.caption2).foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                    .shadow(color: f.color.opacity(0.08), radius: 6, y: 2)
                }
            }
        }
    }

    // MARK: - Plan Selector
    private var planSelector: some View {
        VStack(spacing: 12) {
            Text("Choose your plan")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Annual — highlighted
            PlanCard(
                title:         "Yearly",
                price:         "$49.99",
                period:        "/ year",
                badge:         "BEST VALUE  •  Save 17%",
                detail:        "~$4.17/mo • Billed annually",
                isSelected:    selectedPlan == StoreIDs.annual,
                isRecommended: true,
                accentColor:   accentColor
            ) {
                withAnimation(.spring(response: 0.25)) {
                    selectedPlan = StoreIDs.annual
                }
            }

            // Monthly
            PlanCard(
                title:         "Monthly",
                price:         "$4.99",
                period:        "/ month",
                badge:         nil,
                detail:        "Billed monthly • Cancel anytime",
                isSelected:    selectedPlan == StoreIDs.monthly,
                isRecommended: false,
                accentColor:   accentColor
            ) {
                withAnimation(.spring(response: 0.25)) {
                    selectedPlan = StoreIDs.monthly
                }
            }
        }
    }

    private var annualMonthlyStr: String { "4.17" }

    // MARK: - CTA
    private var ctaSection: some View {
        VStack(spacing: 14) {
            Button { purchase() } label: {
                ZStack {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "crown.fill").font(.system(size: 16))
                            Text("Subscribe Now").font(.headline).bold()
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(isPurchasing ? Color(.systemGray4) : accentColor)
                .cornerRadius(18)
                .shadow(color: accentColor.opacity(isPurchasing ? 0 : 0.45), radius: 12, y: 6)
                .animation(.easeInOut(duration: 0.2), value: isPurchasing)
            }
            .disabled(isPurchasing)

            if isRestoring {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Restoring…").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Footer
    private var footerLinks: some View {
        VStack(spacing: 12) {
            Button("Restore Purchases") { restore() }
                .font(.subheadline).bold()
                .foregroundColor(accentColor)

            HStack(spacing: 6) {
                Link("Privacy Policy", destination: AppConstants.privacyPolicyURL)
                Text("·").foregroundColor(.secondary)
                Link("Terms of Service", destination: AppConstants.termsOfServiceURL)
            }
            .font(.caption).foregroundColor(.secondary)

            Text("Subscriptions renew automatically. Cancel anytime in Settings → Apple ID → Subscriptions.")
                .font(.caption2).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(accentColor).frame(width: 80, height: 80)
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                }
                Text("Welcome to Hemvo!")
                    .font(.title2).bold()
                Text("Your subscription is now active.")
                    .foregroundColor(.secondary)
            }
            .padding(36)
            .background(Color(.systemBackground))
            .cornerRadius(28)
            .shadow(color: .black.opacity(0.2), radius: 30)
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Actions
    private func purchase() {
        isPurchasing  = true
        errorMessage  = nil
        Task {
            do {
                try await storeKit.purchase(productID: selectedPlan)
                await authVM.refreshSubscriptionStatus()
                withAnimation(.spring(response: 0.4)) { showSuccess = true }
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                dismiss()
            } catch StoreKitError.userCancelled {
                // silent
            } catch {
                errorMessage = error.localizedDescription
            }
            isPurchasing = false
        }
    }

    private func restore() {
        isRestoring  = true
        errorMessage = nil
        Task {
            await storeKit.restorePurchases()
            await authVM.refreshSubscriptionStatus()
            isRestoring = false
            if authVM.isSubscriptionActive { dismiss() }
            else { errorMessage = "No active subscription found." }
        }
    }
}

// MARK: - PlanCard
struct PlanCard: View {
    let title:         String
    let price:         String
    let period:        String
    let badge:         String?
    let detail:        String
    let isSelected:    Bool
    let isRecommended: Bool
    let accentColor:   Color
    let onSelect:      () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Radio
                ZStack {
                    Circle()
                        .stroke(isSelected ? accentColor : Color(.systemGray4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(accentColor).frame(width: 12, height: 12)
                    }
                }
                .animation(.spring(response: 0.25), value: isSelected)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.subheadline).bold()
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(accentColor)
                                .cornerRadius(20)
                        }
                    }
                    Text(detail).font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price).font(.title3).bold()
                    Text(period).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isSelected ? accentColor : Color(.systemGray5),
                        lineWidth: isSelected ? 2 : 1
                    )
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            )
            .shadow(color: isSelected ? accentColor.opacity(0.15) : .black.opacity(0.04),
                    radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView()
        .environmentObject(AuthViewModel())
        .environmentObject(StoreKitService.shared)
}
