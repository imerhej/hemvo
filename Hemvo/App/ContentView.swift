//  ContentView.swift
//  Hemvo
//  Root 5-tab navigation shell.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import Foundation
internal import Combine
internal import UserNotifications

struct ContentView: View {

    @EnvironmentObject var authVM:           AuthViewModel
    @EnvironmentObject var householdService: HouseholdService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab:      Tab  = .dashboard
    @State private var scheduleJumpDate: Date? = nil
    @State private var showGracePopup   = false
    @State private var showRenewPaywall = false

    private var currentRole: HouseholdRole? {
        let uid = authVM.profile?.id.uuidString ?? authVM.userID?.uuidString ?? ""
        return householdService.household?.members.first { $0.id == uid }?.role
    }

    /// Owners and adults can add, edit, and delete. Teens are read-only.
    private var canWrite: Bool {
        guard let role = currentRole else { return true }
        return role.canWrite
    }

    enum Tab: Int, CaseIterable {
        case dashboard, meals, budget, schedule, maintenance

        var title: String {
            switch self {
            case .dashboard:   return "Home"
            case .meals:       return "Meals"
            case .budget:      return "Budget"
            case .schedule:    return "Schedule"
            case .maintenance: return "Fix-It"
            }
        }

        var icon: String {
            switch self {
            case .dashboard:   return "house.fill"
            case .meals:       return "fork.knife"
            case .budget:      return "dollarsign.circle.fill"
            case .schedule:    return "calendar"
            case .maintenance: return "wrench.and.screwdriver.fill"
            }
        }

        var color: Color {
            switch self {
            case .dashboard:   return Color(hex: "#4CAF74") ?? .green
            case .meals:       return Color(hex: "#FF9800") ?? .orange
            case .budget:      return Color(hex: "#2196F3") ?? .blue
            case .schedule:    return Color(hex: "#9C27B0") ?? .purple
            case .maintenance: return Color(hex: "#F44336") ?? .red
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Page content — no native TabView so we control rendering
            Group {

                switch selectedTab {
                case .dashboard:
                    DashboardView(
                        onSwitchToMeals: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                                selectedTab = .meals
                            }
                        },
                        onSwitchToBudget: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                                selectedTab = .budget
                            }
                        },
                        onSwitchToSchedule: { date in
                            scheduleJumpDate = date
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                                selectedTab = .schedule
                            }
                        },
                        onSwitchToMaintenance: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                                selectedTab = .maintenance
                            }
                        }
                    )
                case .meals:       MealPlannerView()
                case .budget:      BudgetDashboardView()
                case .schedule:    FamilyCalendarView(jumpToDate: $scheduleJumpDate)
                case .maintenance: MaintenanceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Add bottom padding so content doesn't hide under bar
            .padding(.bottom, 90)

            LiquidTabBar(selectedTab: $selectedTab)

            // Grace period popup shown on app open while the owner's sub has
            // lapsed but the 5-day window hasn't expired yet. Members get the
            // variant with the "ask the owner to renew" reminder; the owner —
            // who can end up here with local access while the server row says
            // lapsed — gets the renew variant with the same days-left count.
            if showGracePopup {
                if authVM.isOwner {
                    OwnerGracePopup(
                        daysRemaining: authVM.memberGraceDaysRemaining,
                        onRenew: {
                            showGracePopup   = false
                            showRenewPaywall = true
                        },
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.25)) { showGracePopup = false }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                } else {
                    GracePeriodPopup(
                        daysRemaining: authVM.gracePeriodDaysRemaining,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.25)) { showGracePopup = false }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .fullScreenCover(isPresented: $showRenewPaywall) { PaywallView() }
        .onAppear { presentGracePopupIfNeeded() }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Re-present when the app is re-opened from the background, not on
            // every inactive/active flicker (control centre, notification pull).
            if oldPhase == .background && newPhase == .active {
                presentGracePopupIfNeeded()
            }
        }
        .onChange(of: authVM.gracePeriodDaysRemaining) { _, _ in
            // Covers the owner lapsing while the app is already running.
            presentGracePopupIfNeeded()
        }
        .onChange(of: authVM.profile?.subscriptionLapsedAt) { _, _ in
            // Owner-side equivalent: fires when refreshSubscriptionStatus
            // reloads the profile with a freshly stamped (or cleared) lapse.
            presentGracePopupIfNeeded()
        }
    }

    private func presentGracePopupIfNeeded() {
        // Owner: the server row says the sub lapsed (grace clock running or
        // expired) and other members are affected. Member: the shared grace
        // countdown is still running.
        let otherMembers = max(0, (householdService.household?.members.count ?? 0) - 1)
        let shouldShow = authVM.isOwner
            ? (authVM.profile?.subscriptionLapsedAt != nil && otherMembers > 0)
            : authVM.gracePeriodDaysRemaining > 0
        guard shouldShow else {
            showGracePopup = false
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) { showGracePopup = true }
    }
}

// MARK: - GracePeriodPopup

private struct GracePeriodPopup: View {
    @EnvironmentObject var authVM:           AuthViewModel
    @EnvironmentObject var householdService: HouseholdService

    let daysRemaining: Int
    let onDismiss: () -> Void

    @State private var isSendingReminder = false
    @State private var reminderSent      = false

    /// Throttle: one renew reminder per member per day, so a household of
    /// members can't flood the owner with pushes.
    @AppStorage("hemvo_renewReminderSentAt") private var reminderSentAt: Double = 0

    private var ownerName: String {
        guard let h = householdService.household else { return "the owner" }
        return h.members.first { $0.id == h.ownerUserID }?.username ?? "the owner"
    }

    private var alreadyRemindedToday: Bool {
        Date().timeIntervalSince1970 - reminderSentAt < 86_400
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 76, height: 76)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                }

                VStack(spacing: 8) {
                    Text("Subscription Paused")
                        .font(.title3).bold()
                        .multilineTextAlignment(.center)

                    Text("\(ownerName)'s subscription has ended. "
                         + (daysRemaining == 1
                            ? "You have 1 day left before the household is paused."
                            : "You have \(daysRemaining) days left before the household is paused."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Button { sendRenewReminder() } label: {
                        ZStack {
                            if isSendingReminder {
                                ProgressView().tint(.white)
                            } else if reminderSent || alreadyRemindedToday {
                                Label("Reminder Sent", systemImage: "checkmark")
                                    .font(.headline)
                            } else {
                                Text("Ask \(ownerName) to Renew")
                                    .font(.headline)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background((reminderSent || alreadyRemindedToday) ? Color.green.opacity(0.8) : Color.orange)
                        .cornerRadius(14)
                    }
                    .disabled(isSendingReminder || reminderSent || alreadyRemindedToday)

                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
            .padding(28)
            .background(Color(.systemBackground))
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.25), radius: 28, y: 8)
            .padding(.horizontal, 36)
        }
    }

    private func sendRenewReminder() {
        guard let h = householdService.household,
              let ownerID = UUID(uuidString: h.ownerUserID) else { return }
        isSendingReminder = true
        let senderName = authVM.profile?.fullName ?? authVM.profile?.username ?? "A household member"
        let days = daysRemaining
        Task {
            await PushNotificationService.shared.notifyUsers(
                [ownerID],
                title: "Renew your Hemvo subscription",
                body: days == 1
                    ? "\(senderName) asked you to renew — 1 day left before your household is paused."
                    : "\(senderName) asked you to renew — \(days) days left before your household is paused."
            )
            isSendingReminder = false
            reminderSent      = true
            reminderSentAt    = Date().timeIntervalSince1970
            // Give the confirmation state a beat, then close.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            onDismiss()
        }
    }
}

// MARK: - LiquidTabBar  (iOS 26 Liquid Glass style)
struct LiquidTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    var visibleTabs: [ContentView.Tab] = ContentView.Tab.allCases
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                LiquidTabItem(
                    tab:        tab,
                    isSelected: selectedTab == tab,
                    animation:  animation
                ) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(
            ZStack {
                // Base glass layer
                RoundedRectangle(cornerRadius: 36)
                    .fill(.ultraThinMaterial)

                // Subtle light refraction tint
                RoundedRectangle(cornerRadius: 36)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Top specular highlight — the key liquid glass detail
                RoundedRectangle(cornerRadius: 36)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint:   .bottomTrailing
                        ),
                        lineWidth: 1
                    )

                // Inner bottom shadow line for depth
                RoundedRectangle(cornerRadius: 36)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: -6)
            .shadow(color: .black.opacity(0.06), radius: 6,  x: 0, y: -1)
        )
        .padding(.horizontal, 14)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - LiquidTabItem
struct LiquidTabItem: View {
    let tab:        ContentView.Tab
    let isSelected: Bool
    var animation:  Namespace.ID
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {

                ZStack {
                    // Liquid glass pill for selected state
                    if isSelected {
                        GlassPill(color: tab.color)
                            .matchedGeometryEffect(id: "pill", in: animation)
                            .frame(width: 56, height: 34)
                    }

                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isSelected ? .white : tab.color)
                        .scaleEffect(isSelected ? 1.12 : 1.0)
                        .shadow(
                            color: isSelected ? tab.color.opacity(0.5) : .clear,
                            radius: 4, x: 0, y: 2
                        )
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.65),
                            value: isSelected
                        )
                }
                .frame(width: 56, height: 34)

                Text(tab.title)
                    .font(.system(size: 10,
                                  weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? tab.color : Color(.systemGray2))
                    .animation(.easeInOut(duration: 0.18), value: isSelected)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }
}

// MARK: - GlassPill  (the selected-tab indicator)
struct GlassPill: View {
    let color: Color
    @State private var shimmer = false

    var body: some View {
        ZStack {
            // Colored fill
            Capsule()
                .fill(color.opacity(0.82))

            // Frosted overlay
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.3))

            // Shimmer highlight that drifts left→right
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(shimmer ? 0.38 : 0.18),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: shimmer ? .leading : .trailing,
                        endPoint:   shimmer ? .trailing : .leading
                    )
                )

            // Top specular edge
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.65),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .top,
                        endPoint:   .bottom
                    ),
                    lineWidth: 1
                )
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.2).repeatForever(autoreverses: true)
            ) { shimmer = true }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(HouseholdService.shared)
        .environmentObject(StoreKitService.shared)
        .environment(\.managedObjectContext,
                     PersistenceService.preview.container.viewContext)
}
