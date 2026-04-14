//  DashboardView.swift
//  HomeBase
//  Home screen — greeting, summary cards, and section previews.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

struct DashboardView: View {

    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var mealVM        = MealPlanViewModel()
    @StateObject private var groceryVM     = GroceryViewModel()
    @StateObject private var budgetVM      = BudgetViewModel()
    @StateObject private var scheduleVM    = ScheduleViewModel()
    @StateObject private var maintenanceVM = MaintenanceViewModel()

    // Reads user's chosen avatar/accent color — updates live when changed in Profile
    @AppStorage("hb_avatarColor") private var avatarColor: String = "#4CAF74"

    @State private var showSettings    = false
    @State private var showGrocery     = false
    @State private var showMeals       = false
    @State private var showBudget      = false
    @State private var showMaintenance = false
    @State private var calendarTarget: Date? = nil
    @State private var showCalendar    = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.homeBaseBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // ── Hero header with embedded calendar ──
                        heroHeader

                        // ── Content below hero ──
                        VStack(spacing: 18) {
                            summaryGrid
                                .padding(.horizontal)
                                .padding(.top, 20)

                            if authVM.trialDaysRemaining > 0 {
                                trialBanner.padding(.horizontal)
                            }

                            upcomingEventsSection.padding(.horizontal)
                            grocerySection.padding(.horizontal)
                            maintenanceSection.padding(.horizontal)
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear { maintenanceVM.seedDefaultsIfNeeded() }
            .navigationDestination(isPresented: $showMeals)       { MealPlannerView() }
            .navigationDestination(isPresented: $showBudget)      { BudgetDashboardView() }
            .navigationDestination(isPresented: $showMaintenance) { MaintenanceView() }
            .navigationDestination(isPresented: $showCalendar) {
                CalendarDetailView(
                    targetDate: calendarTarget ?? Date(),
                    scheduleVM: scheduleVM
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showGrocery) {
            GroceryListView(groceryVM: groceryVM)
        }
    }

    // MARK: - Hero Header with Calendar
    private var heroHeader: some View {
        ZStack(alignment: .top) {
            // Forest green gradient background
            LinearGradient(
                colors: [
                    Color(hex: "#0A2E1A") ?? .green,   // deep forest
                    Color(hex: "#1B5E34") ?? .green,   // mid forest
                    Color(hex: "#2E7D52") ?? .green    // lighter forest
                ],
                startPoint: .topLeading,
                endPoint:   .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            // Decorative circles
            Circle().fill(Color.white.opacity(0.05)).frame(width: 200).offset(x: 140, y: -30)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 120).offset(x: -60, y: 120)

            VStack(spacing: 0) {
                // ── Top bar ──
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting)
                            .font(.caption).foregroundColor(.white.opacity(0.8))
                        Text(authVM.currentUser?.firstName ?? "there")
                            .font(.title2).bold().foregroundColor(.white)
                    }
                    Spacer()
                    Button { showSettings = true } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 40, height: 40)
                            Text(authVM.currentUser?.initials ?? "HB")
                                .font(.subheadline).bold()
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // ── Inline mini calendar ──
                VStack(spacing: 8) {
                    // Month label
                    Text(Date().monthYearDisplay)
                        .font(.caption).bold()
                        .foregroundColor(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // Day strip
                    MiniCalendarStrip(
                        scheduleVM: scheduleVM,
                        onDayTap: { date in
                            calendarTarget = date
                            showCalendar = true
                        }
                    )
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(minHeight: 200)
    }

    // MARK: - Trial Banner
    private var trialBanner: some View {
        NavigationLink(destination: PaywallView()) {
            HStack(spacing: 10) {
                Image(systemName: "clock.fill").foregroundColor(.orange)
                Text("\(authVM.trialDaysRemaining) day\(authVM.trialDaysRemaining == 1 ? "" : "s") left in free trial")
                    .font(.subheadline).bold().foregroundColor(.primary)
                Spacer()
                Text("Upgrade →")
                    .font(.caption).bold().foregroundColor(.homeBaseGreen)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Summary Grid
    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            DashStatCard(value: "\(mealVM.todaysMeals.count) planned",
                         label: "Today's Meals", icon: "fork.knife",
                         color: .orange, buttonLabel: "Planner") { showMeals = true }
            DashStatCard(value: "$\(Int(budgetVM.remainingBudget)) left",
                         label: "Monthly Budget", icon: "dollarsign.circle.fill",
                         color: .blue, buttonLabel: "Budget") { showBudget = true }
            DashStatCard(value: "\(scheduleVM.tasksDueToday.count) due",
                         label: "Tasks Today", icon: "checklist",
                         color: .purple, buttonLabel: "Schedule") {
                calendarTarget = Date(); showCalendar = true
            }
            DashStatCard(value: "\(maintenanceVM.overdueItems.count) overdue",
                         label: "Maintenance", icon: "wrench.and.screwdriver.fill",
                         color: .red, buttonLabel: "Fix-It") { showMaintenance = true }
        }
    }

    // MARK: - Upcoming Events
    private var upcomingEventsSection: some View {
        DashboardCard(
            title: "Upcoming Events", icon: "calendar",
            iconColor: .purple,
            actionLabel: "Full Calendar",
            action: { calendarTarget = Date(); showCalendar = true }
        ) {
            if scheduleVM.upcomingEvents.isEmpty {
                InlineEmptyState(icon: "calendar.badge.plus", message: "No upcoming events")
            } else {
                VStack(spacing: 0) {
                    ForEach(scheduleVM.upcomingEvents.prefix(4)) { event in
                        Button {
                            // Navigate straight to the event's day
                            calendarTarget = event.date
                            showCalendar   = true
                        } label: {
                            DashEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        if event.id != scheduleVM.upcomingEvents.prefix(4).last?.id {
                            Divider().padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grocery
    private var grocerySection: some View {
        DashboardCard(
            title: "Grocery Needs", icon: "cart.fill",
            iconColor: .orange,
            actionLabel: groceryVM.uncheckedItems.isEmpty ? nil : "View List",
            action: { showGrocery = true }
        ) {
            if groceryVM.uncheckedItems.isEmpty {
                AllClearView(message: "Pantry is stocked!")
            } else {
                VStack(spacing: 0) {
                    ForEach(groceryVM.uncheckedItems.prefix(3)) { item in
                        Button { showGrocery = true } label: {
                            DashGroceryRow(item: item)
                        }
                        .buttonStyle(.plain)
                        if item.id != groceryVM.uncheckedItems.prefix(3).last?.id {
                            Divider().padding(.vertical, 3)
                        }
                    }
                    if groceryVM.uncheckedItems.count > 3 {
                        Text("+ \(groceryVM.uncheckedItems.count - 3) more")
                            .font(.caption).foregroundColor(.homeBaseGreen)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }

    // MARK: - Maintenance
    private var maintenanceSection: some View {
        DashboardCard(
            title: "Maintenance Alerts", icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            actionLabel: (maintenanceVM.overdueItems.isEmpty && maintenanceVM.dueSoonItems.isEmpty) ? nil : "View All",
            action: { showMaintenance = true }
        ) {
            let alerts = maintenanceVM.overdueItems + maintenanceVM.dueSoonItems
            if alerts.isEmpty {
                AllClearView(message: "All maintenance is up to date!")
            } else {
                VStack(spacing: 0) {
                    ForEach(alerts.prefix(3)) { item in
                        Button { showMaintenance = true } label: {
                            DashMaintenanceRow(item: item)
                        }
                        .buttonStyle(.plain)
                        if item.id != alerts.prefix(3).last?.id {
                            Divider().padding(.vertical, 3)
                        }
                    }
                    if alerts.count > 3 {
                        Text("+ \(alerts.count - 3) more")
                            .font(.caption).foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }

    // MARK: - Greeting
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

// MARK: - MiniCalendarStrip (embedded in hero)
struct MiniCalendarStrip: View {
    @ObservedObject var scheduleVM: ScheduleViewModel
    let onDayTap: (Date) -> Void

    @State private var selectedDate = Date()

    private var days: [Date] {
        let cal   = Calendar.current
        let start = cal.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        return (0..<14).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let isSelected = day.isSameDay(as: selectedDate)
                    let isToday    = day.isToday
                    let hasEvent   = scheduleVM.hasActivity(on: day)

                    Button {
                        selectedDate = day
                        onDayTap(day)
                    } label: {
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.7))
                            ZStack {
                                Circle()
                                    .fill(isSelected
                                          ? Color.white
                                          : (isToday ? Color.white.opacity(0.2) : Color.clear))
                                    .frame(width: 34, height: 34)
                                Text(day.formatted(.dateTime.day()))
                                    .font(.system(size: 15, weight: isToday ? .bold : .regular))
                                    .foregroundColor(
                                        isSelected
                                        ? Color(hex: "#1565C0") ?? .blue   // dark blue on white circle
                                        : .white
                                    )
                            }
                            // Event dot
                            Circle()
                                .fill(hasEvent
                                      ? (isSelected ? Color(hex: "#1565C0") ?? .blue : Color.white.opacity(0.9))
                                      : Color.clear)
                                .frame(width: 4, height: 4)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - CalendarDetailView (navigated to with a target date)
struct CalendarDetailView: View {
    let targetDate: Date
    @ObservedObject var scheduleVM: ScheduleViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedDate: Date

    init(targetDate: Date, scheduleVM: ScheduleViewModel) {
        self.targetDate  = targetDate
        self.scheduleVM  = scheduleVM
        _selectedDate    = State(initialValue: targetDate)
    }

    var body: some View {
        ZStack {
            Color.homeBaseBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                // Full calendar strip
                CalendarStrip(selectedDate: $selectedDate, vm: scheduleVM)
                    .background(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                ScrollView {
                    VStack(spacing: 16) {

                        // Events for selected date
                        CardView(
                            title: selectedDate.relativeLabel + " — Events",
                            icon:  "calendar", iconColor: .purple,
                            actionLabel: "Add",
                            action: {}
                        ) {
                            let dayEvents = scheduleVM.events(on: selectedDate)
                            if dayEvents.isEmpty {
                                InlineEmptyState(icon: "calendar.badge.plus", message: "No events on this day.")
                            } else {
                                ForEach(dayEvents) { event in
                                    EventDetailRow(
                                        event: event,
                                        member: scheduleVM.member(for: event.assignedToID),
                                        onDelete: { scheduleVM.deleteEvent(event) }
                                    )
                                    if event.id != dayEvents.last?.id { Divider() }
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Tasks for selected date
                        CardView(
                            title: selectedDate.relativeLabel + " — Tasks",
                            icon:  "checklist", iconColor: .blue
                        ) {
                            let dayTasks = scheduleVM.tasks(on: selectedDate)
                            if dayTasks.isEmpty {
                                InlineEmptyState(icon: "checkmark.circle", message: "No tasks due on this day.")
                            } else {
                                ForEach(dayTasks) { task in
                                    TaskDetailRow(
                                        task:     task,
                                        member:   scheduleVM.member(for: task.assignedToID),
                                        onToggle: { scheduleVM.toggleTask(task) },
                                        onDelete: { scheduleVM.deleteTask(task) }
                                    )
                                    if task.id != dayTasks.last?.id { Divider() }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                    .padding(.top, 16)
                }
            }
        }
        .navigationTitle(selectedDate.relativeLabel)
        .navigationBarTitleDisplayMode(.inline)
        .tint(.blue)
    }
}

// MARK: - DashStatCard
struct DashStatCard: View {
    let value:       String
    let label:       String
    let icon:        String
    let color:       Color
    let buttonLabel: String
    let action:      () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(color.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.subheadline).foregroundColor(color)
                }
                Spacer(minLength: 10)
                Text(value).font(.headline).bold().foregroundColor(.primary)
                Text(label).font(.caption).foregroundColor(.secondary)
                Spacer(minLength: 10)
                HStack(spacing: 3) {
                    Text(buttonLabel).font(.caption2).bold().foregroundColor(color)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(color)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(18)
            .shadow(color: color.opacity(0.1), radius: 8, y: 3)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DashboardCard
struct DashboardCard<Content: View>: View {
    let title:       String
    let icon:        String
    let iconColor:   Color
    var actionLabel: String?
    var action:      (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(iconColor).font(.subheadline)
                Text(title).font(.headline)
                Spacer()
                if let label = actionLabel, let action {
                    Button(action: action) {
                        HStack(spacing: 3) {
                            Text(label).font(.caption).bold()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(iconColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(iconColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            content()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

// MARK: - Row Subviews
private struct DashEventRow: View {
    let event: CalendarEvent
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: event.colorHex) ?? .purple)
                .frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.subheadline).bold().foregroundColor(.primary)
                Text(event.date.relativeLabel + (event.isAllDay ? " · All day" : " · \(event.formattedTime)"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct DashGroceryRow: View {
    let item: GroceryItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle").font(.caption).foregroundColor(.secondary)
            Text(item.name).font(.subheadline).foregroundColor(.primary)
            Spacer()
            Text(item.displayQuantity).font(.caption).foregroundColor(.secondary)
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct DashMaintenanceRow: View {
    let item: MaintenanceItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isOverdue ? "exclamationmark.circle.fill" : "clock.fill")
                .foregroundColor(item.isOverdue ? .red : .orange).font(.caption)
            Text(item.title).font(.subheadline).foregroundColor(.primary)
            Spacer()
            Text(item.statusLabel).font(.caption).bold()
                .foregroundColor(item.isOverdue ? .red : .orange)
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DashboardView().environmentObject(AuthViewModel())
}
