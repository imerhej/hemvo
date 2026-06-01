// SettingsView.swift
// Hemvo
// Redesigned: navy/slate palette, grouped cards, subtitles on toggles,
// schedule events notification toggle added.
// Updated for Supabase: authVM.currentUser → authVM.profile (HemvoProfile)

internal import SwiftUI
internal import StoreKit
internal import UserNotifications

struct SettingsView: View {

    @EnvironmentObject var authVM:   AuthViewModel
    @EnvironmentObject var storeKit: StoreKitService
    @EnvironmentObject var prefs:    UserPreferences
    @Environment(\.dismiss) var dismiss

    private var avatarColor: String { prefs.avatarColor }

    // Navigation sheets
    @State private var showProfile       = false
    @State private var showHousehold     = false
    @State private var showSubscription  = false
    @State private var showPaywall       = false
    @State private var showSignOutAlert  = false
    @State private var showNotifAlert    = false
    @State private var showDeleteAlert      = false
    @State private var showDeleteConfirm    = false
    @State private var deleteErrorMessage: String? = nil

    private var isRestrictedRole: Bool {
        let role = authVM.profile?.role ?? ""
        return role == "Teen" || role == "Child"
    }
    private var memberPermissions: MemberPermissions? { authVM.profile?.permissions }

    // Returns true when the owner has explicitly disabled this notification for a restricted member.
    private func ownerLocked(_ perm: Bool?) -> Bool {
        isRestrictedRole && perm == false
    }

    private var billNotifs: Binding<Bool> {
        Binding(
            get: { ownerLocked(memberPermissions?.receiveExpenseAlerts)     ? false : prefs.notifBills },
            set: { if !ownerLocked(memberPermissions?.receiveExpenseAlerts)     { prefs.notifBills       = $0 } }
        )
    }
    private var mealNotifs: Binding<Bool> {
        Binding(
            get: { ownerLocked(memberPermissions?.receiveMealAlerts)        ? false : prefs.notifMeals },
            set: { if !ownerLocked(memberPermissions?.receiveMealAlerts)        { prefs.notifMeals       = $0 } }
        )
    }
    private var scheduleNotifs: Binding<Bool> {
        Binding(
            get: { ownerLocked(memberPermissions?.receiveCalendarAlerts)    ? false : prefs.notifSchedule },
            set: { if !ownerLocked(memberPermissions?.receiveCalendarAlerts)    { prefs.notifSchedule    = $0 } }
        )
    }
    private var maintenanceNotifs: Binding<Bool> {
        Binding(
            get: { ownerLocked(memberPermissions?.receiveMaintenanceAlerts) ? false : prefs.notifMaintenance },
            set: { if !ownerLocked(memberPermissions?.receiveMaintenanceAlerts) { prefs.notifMaintenance = $0 } }
        )
    }

    private var hasAnyOwnerLock: Bool {
        guard isRestrictedRole, let p = memberPermissions else { return false }
        return !p.receiveExpenseAlerts || !p.receiveMealAlerts
            || !p.receiveCalendarAlerts || !p.receiveMaintenanceAlerts
    }

    @State private var systemNotifsGranted = true

    private var accent: Color { Color(hex: avatarColor) ?? .homeBaseGreen }

    // ── Profile helpers (from Supabase HemvoProfile) ───────────────────────
    // Cached so they don't flash to placeholder when signOut() nils the profile.
    @State private var displayName:  String = "Hemvo User"
    @State private var displayEmail: String = ""
    @State private var initials:     String = "HV"

    private func syncProfileCache() {
        guard let p = authVM.profile else { return }
        displayName  = p.fullName ?? "Hemvo User"
        displayEmail = p.email    ?? ""
        let parts    = (p.fullName ?? "").split(separator: " ").prefix(2)
        let joined   = parts.map { String($0.prefix(1)).uppercased() }.joined()
        initials     = joined.isEmpty ? "HV" : joined
    }

    // ── Subscription helpers ───────────────────────────────────────────────
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
                        accountGroup
                        notificationsGroup
                            .disabled(!systemNotifsGranted)
                        preferenceSyncGroup
                        aboutGroup
                        signOutButton
                        dangerZone
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
        .onAppear {
            checkNotifPermission()
            syncProfileCache()
        }
        .onChange(of: authVM.profile) { _, _ in syncProfileCache() }
        .sheet(isPresented: $showProfile)      { ProfileView() }
        .sheet(isPresented: $showHousehold)    { HouseholdMembersView() }
        .sheet(isPresented: $showSubscription) { SubscriptionStatusView() }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) { authVM.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to sign out of Hemvo?")
        }
        .alert("Delete Account", isPresented: $showDeleteAlert) {
            Button("Continue", role: .destructive) { showDeleteConfirm = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and remove all Hemvo data from this device — meals, budget, schedule, maintenance, and your login. This cannot be undone.")
        }
        .alert("Are you absolutely sure?", isPresented: $showDeleteConfirm) {
            Button("Delete My Account", role: .destructive) {
                Task {
                    if let error = await authVM.deleteAccount() {
                        deleteErrorMessage = error
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your account and all local data will be erased immediately. There is no way to recover this.")
        }
        .alert("Deletion Failed", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert("Notifications Blocked", isPresented: $showNotifAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Enable notifications in Settings → Hemvo → Notifications to receive reminders.")
        }
    }

    // MARK: - Hero Header
    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [accent, accent.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            .animation(.easeInOut(duration: 0.3), value: avatarColor)

            Circle().fill(Color.white.opacity(0.07)).frame(width: 240).offset(x: 120, y: -50)
            Circle().fill(Color.white.opacity(0.05)).frame(width: 150).offset(x: -80, y: 60)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 90).offset(x: 60, y: 70)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 72, height: 72)
                        Text(initials)
                            .font(.system(size: 24, weight: .black))
                            .foregroundColor(.white)
                    }
                    .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)

                    // Name + email — from Supabase profile
                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayName)
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                        Text(displayEmail)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .padding(.top, 6)

                    Spacer()

                    // Sign out button
                    Button { showSignOutAlert = true } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            Text("Sign out")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }

                // Subscription badge — only the owner can manage/upgrade
                if authVM.isOwner {
                    HStack(spacing: 8) {
                        Image(systemName: subIcon)
                            .font(.system(size: 11, weight: .bold))
                        Text(subLabel)
                            .font(.system(size: 12, weight: .heavy))
                            .kerning(0.2)
                        Spacer()
                        Text(isActive ? "Manage →" : "Upgrade →")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundColor(accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.92))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
                    .padding(.top, 16)
                    .onTapGesture { isActive ? (showSubscription = true) : (showPaywall = true) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 22)
        }
        .frame(minHeight: 170)
    }

    // MARK: - Account Group
    private var accountGroup: some View {
        SettingsGroup(header: "ACCOUNT", headerIcon: "person.fill") {
            SettingsNavRow(icon: "person.circle.fill",  color: accent,                  label: "Edit Profile",         chevron: true) { showProfile = true }
            SettingsDivider()
            SettingsNavRow(icon: "house.fill",           color: Color(hex: "#1565C0")!, label: "Household Members",   chevron: true) { showHousehold = true }
            if authVM.isOwner {
                SettingsDivider()
                SettingsNavRow(icon: "crown.fill",      color: Color(hex: "#E67E22")!, label: "Manage Subscription", chevron: true) { showSubscription = true }
                SettingsDivider()
                SettingsNavRow(icon: "arrow.clockwise", color: Color(hex: "#2E7D32")!, label: "Restore Purchases",   chevron: false) {
                    Task { await storeKit.restorePurchases() }
                }
            }
        }
    }

    // MARK: - Notifications Group
    private var notificationsGroup: some View {
        SettingsGroup(header: "NOTIFICATIONS", headerIcon: "bell.fill") {
            if hasAnyOwnerLock {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.bpTextSub)
                    Text("Some notifications are managed by your household owner")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.bpTextSub)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.bpDivider.opacity(0.5))
                Color.bpDivider.frame(height: 1)
            }

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
                isOn: billNotifs
            )
            .disabled(ownerLocked(memberPermissions?.receiveExpenseAlerts))
            .onChange(of: prefs.notifBills) { _, enabled in
                if !enabled { NotificationService.shared.cancelAllBillReminders() }
            }
            SettingsDivider()
            SettingsToggleRow(
                icon: "fork.knife.circle.fill", color: Color(hex: "#E67E22")!,
                label: "Meal Plan Reminders",
                detail: "Daily meal planning nudges",
                tint: Color(hex: "#E67E22")!,
                isOn: mealNotifs
            )
            .disabled(ownerLocked(memberPermissions?.receiveMealAlerts))
            .onChange(of: prefs.notifMeals) { _, enabled in
                if !enabled { NotificationService.shared.cancelMealReminders() }
            }
            SettingsDivider()
            SettingsToggleRow(
                icon: "calendar.badge.clock", color: Color(hex: "#6A1B9A")!,
                label: "Schedule Events",
                detail: "Upcoming event & task alerts",
                tint: Color(hex: "#6A1B9A")!,
                isOn: scheduleNotifs
            )
            .disabled(ownerLocked(memberPermissions?.receiveCalendarAlerts))
            .onChange(of: prefs.notifSchedule) { _, enabled in
                if !enabled { NotificationService.shared.cancelAllEventReminders() }
            }
            SettingsDivider()
            SettingsToggleRow(
                icon: "wrench.and.screwdriver.fill", color: Color(hex: "#4E342E")!,
                label: "Maintenance Reminders",
                detail: "Home upkeep task alerts",
                tint: Color(hex: "#4E342E")!,
                isOn: maintenanceNotifs
            )
            .disabled(ownerLocked(memberPermissions?.receiveMaintenanceAlerts))
            .onChange(of: prefs.notifMaintenance) { _, enabled in
                if !enabled { NotificationService.shared.cancelAllMaintenanceReminders() }
            }
        }
    }

    // MARK: - Preference Sync Group
    private var preferenceSyncGroup: some View {
        SettingsGroup(header: "PREFERENCES SYNC", headerIcon: "icloud.fill") {
            HStack(spacing: 14) {
                SettingsIconBox(icon: "icloud.fill", color: Color(hex: "#00838F")!)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Preferences")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.bpText)
                    Text("Notification settings & avatar color sync across your devices")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(Color.bpTextSub)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundColor(Color(hex: "#2E7D32")!)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    // MARK: - About Group
    private var aboutGroup: some View {
        SettingsGroup(header: "ABOUT", headerIcon: "info.circle.fill") {
            HStack(spacing: 14) {
                SettingsIconBox(icon: "house.circle.fill", color: Color.bpNavy)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hemvo")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.bpText)
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

            Button {
                if let url = URL(string: "https://apps.apple.com/app/hemvo") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 14) {
                    SettingsIconBox(icon: "star.fill", color: Color(hex: "#E67E22")!)
                    Text("Rate Hemvo")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.bpText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.bpTextSub.opacity(0.5))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .contentShape(Rectangle())
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

    // MARK: - Danger Zone
    private var dangerZone: some View {
        SettingsGroup(header: "DANGER ZONE", headerIcon: "exclamationmark.triangle.fill") {
            Button { showDeleteAlert = true } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                        Image(systemName: "person.crop.circle.badge.minus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete Account")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red)
                        Text("Permanently erase all data from this device")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.bpTextSub)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.red.opacity(0.4))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

struct SettingsGroup<Content: View>: View {
    var title:      String = ""
    var header:     String = ""
    var headerIcon: String = ""
    let content:    () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title      = title
        self.header     = title.uppercased()
        self.headerIcon = ""
        self.content    = content
    }

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

struct SettingsDivider: View {
    var body: some View {
        Color.bpDivider.frame(height: 1).padding(.leading, 56)
    }
}

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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsToggleRow: View {
    let icon:   String
    let color:  Color
    let label:  String
    var detail: String = ""
    var tint:   Color  = Color.bpNavy
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
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
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.bpTextSub.opacity(0.5))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthViewModel())
            .environmentObject(StoreKitService.shared)
            .environmentObject(UserPreferences.shared)
    }
}
