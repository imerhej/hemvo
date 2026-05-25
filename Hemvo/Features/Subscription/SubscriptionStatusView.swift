//  SubscriptionStatusView.swift
//  Hemvo
//  Redesigned: premium dark hero, clear status, all buttons always visible.

internal import SwiftUI
internal import StoreKit

struct SubscriptionStatusView: View {

    @EnvironmentObject var authVM:   AuthViewModel
    @EnvironmentObject var storeKit: StoreKitService
    @Environment(\.dismiss) var dismiss

    @State private var isRefreshing   = false
    @State private var showPaywall    = false
    @State private var showCancelInfo = false

    // MARK: - Derived state
    private var isTrial:   Bool { authVM.trialDaysRemaining > 0 }
    private var isActive:  Bool { authVM.isSubscriptionActive && !isTrial }
    private var isExpired: Bool { !authVM.isSubscriptionActive }

    private var statusColor: Color {
        if isTrial  { return Color(hex: "#E67E22")! }
        if isActive { return Color(hex: "#2E7D32")! }
        return .red
    }
    private var statusGradient: [Color] {
        if isTrial  { return [Color(hex: "#E67E22")!, Color(hex: "#F39C12")!] }
        if isActive { return [Color(hex: "#1B5E20")!, Color(hex: "#2E7D32")!] }
        return [Color(hex: "#B71C1C")!, Color(hex: "#E53935")!]
    }
    private var statusIcon: String {
        isTrial ? "clock.fill" : isActive ? "checkmark.seal.fill" : "xmark.seal.fill"
    }
    private var statusTitle: String {
        isTrial ? "Free Trial" : isActive ? "Premium Active" : "Subscription Expired"
    }
    private var statusSubtitle: String {
        if isTrial  { return "\(authVM.trialDaysRemaining) day\(authVM.trialDaysRemaining == 1 ? "" : "s") remaining" }
        if isActive { return "Full access to all Hemvo features" }
        return "Renew to restore access"
    }
    private var activePlan: String {
        if storeKit.purchasedProductIDs.contains(StoreIDs.annual)  { return "Yearly Plan · \(storeKit.formattedPrice(for: StoreIDs.annual))/yr" }
        if storeKit.purchasedProductIDs.contains(StoreIDs.monthly) { return "Monthly Plan · \(storeKit.formattedPrice(for: StoreIDs.monthly))/mo" }
        return "Hemvo Premium"
    }
    private var trialProgress: Double {
        let used = AppConstants.trialDurationDays - authVM.trialDaysRemaining
        return Double(used) / Double(AppConstants.trialDurationDays)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#F4F6FB")!.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        heroCard          .padding(.horizontal, 20).padding(.top, 20)
                        if isActive  { planDetailsCard  .padding(.horizontal, 20) }
                        if isTrial   { trialProgressCard.padding(.horizontal, 20) }
                        featuresCard      .padding(.horizontal, 20)
                        actionButtons     .padding(.horizontal, 20).padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.bpSlate)
                }
            }
            .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
            .alert("Cancel Subscription", isPresented: $showCancelInfo) {
                Button("Open App Store Settings") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not Now", role: .cancel) { }
            } message: {
                Text("To cancel, go to Settings → Apple ID → Subscriptions and select Hemvo.")
            }
        }
    }

    // MARK: - Hero Card
    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: statusGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(Color.white.opacity(0.06)).frame(width: 180).offset(x: 100, y: -50)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 120).offset(x: -80, y: 60)

            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.15)).frame(width: 80, height: 80)
                    Circle().fill(Color.white.opacity(0.22)).frame(width: 62, height: 62)
                    Image(systemName: statusIcon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.white)
                    Text(statusSubtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                Text(isTrial ? "TRIAL" : isActive ? "PREMIUM" : "EXPIRED")
                    .font(.system(size: 10, weight: .heavy)).kerning(2)
                    .foregroundColor(statusGradient.first ?? .white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.white)
                    .cornerRadius(20)
            }
            .padding(.vertical, 32)
        }
        .shadow(color: (statusGradient.first ?? .gray).opacity(0.4), radius: 20, y: 8)
    }

    // MARK: - Plan Details Card
    private var planDetailsCard: some View {
        VStack(spacing: 0) {
            sectionHeader(icon: "star.circle.fill", title: "PLAN DETAILS", color: Color(hex: "#2E7D32")!)
            Color.bpDivider.frame(height: 1)
            planRow("Current Plan",  activePlan,                   Color.bpText)
            Color.bpDivider.frame(height: 1).padding(.leading, 16)
            planRow("Status",        "Active",                      Color(hex: "#2E7D32")!)
            Color.bpDivider.frame(height: 1).padding(.leading, 16)
            planRow("Billing",       "Auto-renews via App Store",  Color.bpTextSub)
        }
        .background(Color.bpSurface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.bpDivider, lineWidth: 1))
        .shadow(color: Color.bpText.opacity(0.04), radius: 8, y: 3)
    }

    private func planRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundColor(Color.bpTextSub)
            Spacer()
            Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: - Trial Progress Card
    private var trialProgressCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill").font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: "#E67E22")!)
                Text("TRIAL PROGRESS").font(.system(size: 10, weight: .heavy)).kerning(1.5).foregroundColor(Color.bpTextSub)
                Spacer()
                Text("\(authVM.trialDaysRemaining) days left").font(.system(size: 12, weight: .heavy)).foregroundColor(Color(hex: "#E67E22")!)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(hex: "#E67E22")!.opacity(0.15)).frame(height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [Color(hex: "#E67E22")!, Color(hex: "#F39C12")!], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * trialProgress, height: 10)
                        .animation(.spring(response: 0.5), value: trialProgress)
                }
            }
            .frame(height: 10)
            HStack {
                Text("Day \(AppConstants.trialDurationDays - authVM.trialDaysRemaining) of \(AppConstants.trialDurationDays)")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(Color.bpTextSub)
                Spacer()
                Text("\(Int(trialProgress * 100))% used").font(.system(size: 12, weight: .heavy)).foregroundColor(Color(hex: "#E67E22")!)
            }
        }
        .padding(16)
        .background(Color.bpSurface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "#E67E22")!.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.bpText.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - Features Card
    private var featuresCard: some View {
        VStack(spacing: 0) {
            sectionHeader(icon: "sparkles", title: "WHAT'S INCLUDED", color: Color.bpNavy)
            Color.bpDivider.frame(height: 1)

            let features: [(String, String, Color)] = [
                ("fork.knife.circle.fill",    "Meal Planning & Grocery Lists",       Color(hex: "#E67E22")!),
                ("dollarsign.circle.fill",     "Budget Tracking & Bill Reminders",    Color(hex: "#1565C0")!),
                ("calendar.circle.fill",       "Family Calendar & Task Delegation",   Color(hex: "#6A1B9A")!),
                ("wrench.and.screwdriver",     "Home Maintenance Tracker",            Color(hex: "#B71C1C")!),
                ("person.2.circle.fill",       "Household Members & Invitations",     Color(hex: "#2E7D32")!),
                ("bell.badge.circle.fill",     "Smart Notifications",                 Color(hex: "#E67E22")!),
            ]

            ForEach(features, id: \.0) { icon, label, color in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)).frame(width: 34, height: 34)
                        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(color)
                    }
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(Color.bpText)
                    Spacer()
                    Image(systemName: isActive || isTrial ? "checkmark.circle.fill" : "lock.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isActive || isTrial ? Color(hex: "#2E7D32")! : Color.bpTextSub.opacity(0.35))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)

                if label != features.last?.1 {
                    Color.bpDivider.frame(height: 1).padding(.leading, 62)
                }
            }
            .padding(.bottom, 4)
        }
        .background(Color.bpSurface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.bpDivider, lineWidth: 1))
        .shadow(color: Color.bpText.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - Action Buttons — owner-only
    private var actionButtons: some View {
        VStack(spacing: 12) {

            if authVM.isOwner {
                // Upgrade / Renew (non-active subscribers)
                if !isActive {
                    Button { showPaywall = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "crown.fill").font(.system(size: 16))
                            Text(isExpired ? "Renew Subscription" : "Upgrade to Premium")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(
                                colors: isExpired ? [Color(hex: "#B71C1C")!, Color(hex: "#E53935")!]
                                                 : [Color(hex: "#E67E22")!, Color(hex: "#F39C12")!],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: (isExpired ? Color(hex: "#B71C1C")! : Color(hex: "#E67E22")!).opacity(0.4), radius: 12, y: 5)
                    }
                }

                // Restore Purchases
                Button {
                    Task {
                        isRefreshing = true
                        await storeKit.restorePurchases()
                        await authVM.refreshSubscriptionStatus()
                        isRefreshing = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isRefreshing {
                            ProgressView().scaleEffect(0.85).tint(Color.bpNavy)
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill").font(.system(size: 16))
                        }
                        Text(isRefreshing ? "Restoring…" : "Restore Purchases")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(Color.bpNavy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.bpNavyLight)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.bpNavy.opacity(0.2), lineWidth: 1))
                }
                .disabled(isRefreshing)

                // Refresh Status
                Button { refresh() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 15, weight: .semibold))
                        Text("Refresh Status").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(Color.bpSlate)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.bpSurface)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.bpDivider, lineWidth: 1))
                }

                // Cancel Subscription
                if isActive {
                    Button { showCancelInfo = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 15, weight: .semibold))
                            Text("Cancel Subscription").font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.red.opacity(0.07))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.2), lineWidth: 1))
                    }
                }
            }

            // Legal links
            HStack(spacing: 8) {
                Link("Privacy Policy", destination: AppConstants.privacyPolicyURL)
                Text("·").foregroundColor(Color.bpTextSub)
                Link("Terms of Service", destination: AppConstants.termsOfServiceURL)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color.bpTextSub)

            Text("Subscriptions renew automatically. Cancel anytime in Settings → Apple ID → Subscriptions.")
                .font(.system(size: 11))
                .foregroundColor(Color.bpTextSub.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Section Header helper
    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundColor(color)
            Text(title).font(.system(size: 10, weight: .heavy)).kerning(1.5).foregroundColor(Color.bpTextSub)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
    }

    private func refresh() {
        isRefreshing = true
        Task {
            await authVM.refreshSubscriptionStatus()
            try? await Task.sleep(nanoseconds: 600_000_000)
            isRefreshing = false
        }
    }
}

#Preview {
    SubscriptionStatusView()
        .environmentObject(AuthViewModel())
        .environmentObject(StoreKitService.shared)
}
