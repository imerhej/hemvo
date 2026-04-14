//  SettingsView.swift
//  HomeBase
//  Redesigned: navy/slate palette, grouped cards, subtitles on toggles,
//  schedule events notification toggle added.

internal import SwiftUI
internal import StoreKit
internal import UserNotifications

struct SettingsView: View {

    @EnvironmentObject var authVM:   AuthViewModel
    @EnvironmentObject var storeKit: StoreKitService
    @StateObject private var syncService = CloudSyncService.shared
    @Environment(\.dismiss) var dismiss

    @AppStorage("hb_avatarColor")     private var avatarColor: String = "#4CAF74"

    // Navigation sheets
    @State private var showProfile      = false
    @State private var showHousehold    = false
    @State private var showSubscription = false
    @State private var showPaywall      = false
    @State private var showSignOutAlert = false
    @State private var showNotifAlert   = false

    // Notification toggles — all persisted in UserDefaults
    @AppStorage("notif_bills")        private var billNotifs        = true
    @AppStorage("notif_meals")        private var mealNotifs        = true
    @AppStorage("notif_schedule")     private var scheduleNotifs    = true
    @AppStorage("notif_maintenance")  private var maintenanceNotifs = true

    @State private var systemNotifsGranted = true   // false when OS permission denied

    private var accent: Color { Color(hex: avatarColor) ?? .homeBaseGreen }

    // ── Subscription helpers ───────────────────────────────
    private var isTrial:  Bool { authVM.trialDaysRemaining > 0 }
    private var isActive: Bool { authVM.isSubscriptionActive && !isTrial }

    private var subColor: Color {
        isTrial ? Color(hex: "#E67E22")! : isActive ? Color(hex: "#2E7D32")! : .red
    }
    private var subIcon: String {
        isTrial ? "clock.fill" : isActive ? "crown.fill" : "xmark.circle.fill"
    }
    private var subLabel: String {
        isTrial  ? "Free Trial · \(authVM.trialDaysRemaining)d left"
        : isActive ? "Premium Active"
        : "Subscription Expired"
    }
    private var subDetail: String {
        isTrial  ? "Upgrade to keep full access after your trial ends"
        : isActive ? "Tap to manage or cancel your subscription"
        : "Tap to renew and restore full access"
    }

    var body: some View {
        ZStack {
            Color(hex: "#F4F6FB")!.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroHeader
                    VStack(spacing: 18) {
                        subBanner
                        accountGroup
                        notificationsGroup
                        iCloudGroup
                        aboutGroup
                        signOutButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    .padding(.bottom, 52)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.bpSlate)
            }
        }
        .onAppear { checkNotifPermission() }
        .sheet(isPresented: $showProfile)      { ProfileView() }
        .sheet(isPresented: $showHousehold)    { HouseholdMembersView() }
        .sheet(isPresented: $showSubscription) { SubscriptionStatusView() }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) { authVM.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to sign out of HomeBase?")
        }
        .alert("Notifications Blocked", isPresented: $showNotifAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Enable notifications in Settings → HomeBase → Notifications to receive reminders.")
        }
    }

    // MARK: - Hero Header
    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color.bpNavy, Color.bpSlate],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            // Decoration
            Circle().fill(Color.white.opacity(0.05)).frame(width: 220).offset(x: 130, y: -60)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 130).offset(x: -90, y: 50)

            HStack(spacing: 16) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 66, height: 66)
                        .shadow(color: accent.opacity(0.5), radius: 12, y: 4)
                    Text(authVM.currentUser?.initials ?? "HB")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.white)
                }

                // Name + email + sub pill
                VStack(alignment: .leading, spacing: 5) {
                    Text(authVM.currentUser?.name ?? "HomeBase User")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(authVM.currentUser?.email ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                    // Subscription badge
                    HStack(spacing: 5) {
                        Image(systemName: subIcon)
                            .font(.system(size: 9, weight: .bold))
                        Text(subLabel)
                            .font(.system(size: 10, weight: .heavy))
                            .kerning(0.3)
                    }
                    .foregroundColor(subColor)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.white)
                    .cornerRadius(20)
                }

                Spacer()

                // Quick action buttons
                VStack(spacing: 6) {
                    headerIconButton(icon: "pencil", color: .white.opacity(0.9)) { showProfile = true }
                    Text("Edit").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                }
                VStack(spacing: 6) {
                    headerIconButton(icon: "rectangle.portrait.and.arrow.right", color: Color(hex: "#FF6B6B")!) {
                        showSignOutAlert = true
                    }
                    Text("Sign out").font(.system(size: 9, weight: .semibold)).foregroundColor(Color(hex: "#FF6B6B")!.opacity(0.85))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
        }
        .frame(minHeight: 150)
    }

    private func headerIconButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
                .overlay(Circle().stroke(color.opacity(0.25), lineWidth: 1))
        }
    }

    // MARK: - Subscription Banner
    private var subBanner: some View {
        Button {
            isActive ? (showSubscription = true) : (showPaywall = true)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(subColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: subIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(subColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(isTrial ? "Free Trial Active"
                         : isActive ? "Premium Subscription"
                         : "Subscription Expired")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.bpText)
                    Text(subDetail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.bpTextSub)
                        .lineLimit(1)
                }
                Spacer()
                Text(isActive ? "Manage" : "Upgrade")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(subColor)
                    .cornerRadius(20)
            }
            .padding(14)
            .background(Color.bpSurface)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(subColor.opacity(0.2), lineWidth: 1))
            .shadow(color: subColor.opacity(0.1), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Account Group
    private var accountGroup: some View {
        SettingsGroup(header: "ACCOUNT", headerIcon: "person.fill") {
            SettingsNavRow(icon: "person.circle.fill",  color: accent,                  label: "Edit Profile",         chevron: true) { showProfile = true }
            SettingsDivider()
            SettingsNavRow(icon: "house.fill",           color: Color(hex: "#1565C0")!, label: "Household Members",   chevron: true) { showHousehold = true }
            SettingsDivider()
            SettingsNavRow(icon: "crown.fill",           color: Color(hex: "#E67E22")!, label: "Manage Subscription", chevron: true) { showSubscription = true }
            SettingsDivider()
            SettingsNavRow(icon: "arrow.clockwise",      color: Color(hex: "#2E7D32")!, label: "Restore Purchases",   chevron: false) {
                Task { await storeKit.restorePurchases() }
            }
        }
    }

    // MARK: - Notifications Group
    private var notificationsGroup: some View {
        SettingsGroup(header: "NOTIFICATIONS", headerIcon: "bell.fill") {

            // Permission warning
            if !systemNotifsGranted {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange).font(.system(size: 13))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Notifications are disabled")
                                .font(.system(size: 12, weight: .bold)).foregroundColor(Color.bpText)
                            Text("Tap to enable in System Settings")
                                .font(.system(size: 11, weight: .medium)).foregroundColor(Color.bpTextSub)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.orange.opacity(0.07))
                }
                .buttonStyle(.plain)
                Color.bpDivider.frame(height: 1)
            }

            SettingsToggleRow(
                icon: "bell.badge.fill", color: Color(hex: "#C62828")!,
                label: "Bill Reminders",
                detail: "Alerts before bills are due",
                tint: Color(hex: "#C62828")!,
                isOn: $billNotifs
            )
            SettingsDivider()
            SettingsToggleRow(
                icon: "fork.knife.circle.fill", color: Color(hex: "#E67E22")!,
                label: "Meal Plan Reminders",
                detail: "Daily meal planning nudges",
                tint: Color(hex: "#E67E22")!,
                isOn: $mealNotifs
            )
            SettingsDivider()
            SettingsToggleRow(
                icon: "calendar.badge.clock", color: Color(hex: "#6A1B9A")!,
                label: "Schedule Events",
                detail: "Upcoming event & task alerts",
                tint: Color(hex: "#6A1B9A")!,
                isOn: $scheduleNotifs
            )
            SettingsDivider()
            SettingsToggleRow(
                icon: "wrench.and.screwdriver.fill", color: Color(hex: "#4E342E")!,
                label: "Maintenance Reminders",
                detail: "Home upkeep task alerts",
                tint: Color(hex: "#4E342E")!,
                isOn: $maintenanceNotifs
            )
        }
    }

    // MARK: - iCloud Group
    private var iCloudGroup: some View {
        SettingsGroup(header: "iCLOUD SYNC", headerIcon: "icloud.fill") {
            HStack(spacing: 14) {
                SettingsIconBox(icon: "icloud.fill", color: Color(hex: "#00838F")!)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud").font(.system(size: 14, weight: .semibold)).foregroundColor(Color.bpText)
                    Text(syncService.statusDescription)
                        .font(.system(size: 12, weight: .medium)).foregroundColor(Color.bpTextSub)
                }
                Spacer()
                if case .syncing = syncService.syncStatus {
                    ProgressView().scaleEffect(0.8).tint(Color.bpSlate)
                } else {
                    Image(systemName: syncService.isICloudAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(syncService.isICloudAvailable ? Color(hex: "#2E7D32")! : Color.bpTextSub.opacity(0.35))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            SettingsDivider()

            Button { Task { await syncService.triggerSync() } } label: {
                HStack(spacing: 14) {
                    SettingsIconBox(icon: "arrow.triangle.2.circlepath", color: Color(hex: "#00838F")!)
                    Text("Sync Now").font(.system(size: 14, weight: .semibold)).foregroundColor(Color.bpText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.bpTextSub.opacity(0.5))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - About Group
    private var aboutGroup: some View {
        SettingsGroup(header: "ABOUT", headerIcon: "info.circle.fill") {
            // Version
            HStack(spacing: 14) {
                SettingsIconBox(icon: "house.circle.fill", color: Color.bpNavy)
                VStack(alignment: .leading, spacing: 2) {
                    Text("HomeBase").font(.system(size: 14, weight: .semibold)).foregroundColor(Color.bpText)
                    Text("Version \(AppConstants.appVersion) (\(AppConstants.buildNumber))")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(Color.bpTextSub)
                }
                Spacer()
                Text("Latest")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                    .foregroundColor(Color(hex: "#2E7D32")!)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: "#2E7D32")!.opacity(0.1)).cornerRadius(20)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            SettingsDivider()
            SettingsLinkRow(icon: "lock.shield.fill",         color: Color(hex: "#1565C0")!, label: "Privacy Policy",   url: AppConstants.privacyPolicyURL)
            SettingsDivider()
            SettingsLinkRow(icon: "doc.text.fill",            color: Color(hex: "#1565C0")!, label: "Terms of Service", url: AppConstants.termsOfServiceURL)
            SettingsDivider()
            SettingsLinkRow(icon: "questionmark.circle.fill", color: Color(hex: "#6A1B9A")!, label: "Support & Help",   url: AppConstants.supportURL)
            SettingsDivider()

            // Rate the app
            Button {
                if let url = URL(string: "https://apps.apple.com/app/homebase") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 14) {
                    SettingsIconBox(icon: "star.fill", color: Color(hex: "#E67E22")!)
                    Text("Rate HomeBase").font(.system(size: 14, weight: .semibold)).foregroundColor(Color.bpText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.bpTextSub.opacity(0.5))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sign Out Button
    private var signOutButton: some View {
        Button { showSignOutAlert = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                Text("Sign Out")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.red.opacity(0.07))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.18), lineWidth: 1))
        }
    }

    // MARK: - Helpers
    private func checkNotifPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                systemNotifsGranted = settings.authorizationStatus != .denied
            }
        }
    }
}

// MARK: ─── Shared Components ──────────────────────────────────────────────────

// MARK: - SettingsGroup
struct SettingsGroup<Content: View>: View {
    var title: String = ""
    var header: String = ""
    var headerIcon: String = ""
    let content: () -> Content

    // Legacy init (other files may pass title:)
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title      = title
        self.header     = title.uppercased()
        self.headerIcon = ""
        self.content    = content
    }

    // New styled init
    init(header: String, headerIcon: String, @ViewBuilder content: @escaping () -> Content) {
        self.header     = header
        self.headerIcon = headerIcon
        self.content    = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !headerIcon.isEmpty {
                    Image(systemName: headerIcon)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(Color.bpTextSub)
                }
                Text(header.isEmpty ? title.uppercased() : header)
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.4)
                    .foregroundColor(Color.bpTextSub)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) { content() }
                .background(Color.bpSurface)
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.bpDivider, lineWidth: 1))
                .shadow(color: Color.bpText.opacity(0.04), radius: 8, y: 3)
        }
    }
}

// MARK: - SettingsDivider
struct SettingsDivider: View {
    var body: some View {
        Color.bpDivider.frame(height: 1).padding(.leading, 56)
    }
}

// MARK: - SettingsIconBox
struct SettingsIconBox: View {
    let icon:  String
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(color).frame(width: 32, height: 32)
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
        }
    }
}

// MARK: - SettingsNavRow
struct SettingsNavRow: View {
    let icon:    String
    let color:   Color
    let label:   String
    var chevron: Bool = true
    let action:  () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SettingsIconBox(icon: icon, color: color)
                Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(Color.bpText)
                Spacer()
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.bpTextSub.opacity(0.5))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SettingsToggleRow  ← now has detail subtitle + per-toggle tint
struct SettingsToggleRow: View {
    let icon:   String
    let color:  Color
    let label:  String
    var detail: String = ""
    var tint:   Color  = Color.bpNavy
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingsIconBox(icon: icon, color: isOn ? color : Color(hex: "#B0BAC8")!)
                .animation(.easeInOut(duration: 0.2), value: isOn)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOn ? Color.bpText : Color.bpTextSub)
                    .animation(.easeInOut(duration: 0.15), value: isOn)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.bpTextSub.opacity(0.75))
                }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(tint)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

// MARK: - SettingsLinkRow
struct SettingsLinkRow: View {
    let icon:  String
    let color: Color
    let label: String
    let url:   URL
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                SettingsIconBox(icon: icon, color: color)
                Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(Color.bpText)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.bpTextSub.opacity(0.5))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthViewModel())
            .environmentObject(StoreKitService.shared)
    }
}
