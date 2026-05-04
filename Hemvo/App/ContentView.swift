//  ContentView.swift
//  Hemvo
//  Root 5-tab navigation shell.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

struct ContentView: View {

    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab: Tab = .dashboard
    @State private var scheduleJumpDate: Date? = nil

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

            // Custom liquid tab bar
            LiquidTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - LiquidTabBar  (iOS 26 Liquid Glass style)
struct LiquidTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
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
        .environmentObject(StoreKitService.shared)
        .environment(\.managedObjectContext,
                     PersistenceService.preview.container.viewContext)
}
