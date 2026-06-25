// DashboardView.swift
// Hemvo
// Redesigned home screen — warm palette, burger menu → settings only,
// "Full Calendar" switches schedule tab, calendar strip events open detail sheet.

internal import SwiftUI
internal import Combine

struct DashboardView: View {

    @EnvironmentObject var authVM:           AuthViewModel
    @EnvironmentObject var householdService: HouseholdService
    @StateObject private var mealVM        = MealPlanViewModel()
    @StateObject private var groceryVM     = GroceryViewModel()
    @StateObject private var budgetVM      = BudgetViewModel()
    @StateObject private var scheduleVM    = ScheduleViewModel()
    @StateObject private var maintenanceVM = MaintenanceViewModel()

    @AppStorage("hemvo_avatarColor") private var avatarColor: String = "#C8922A"

    /// Tab-switching callbacks injected by ContentView
    var onSwitchToMeals:       (() -> Void)?     = nil
    var onSwitchToBudget:      (() -> Void)?     = nil
    var onSwitchToSchedule:    ((Date) -> Void)? = nil
    var onSwitchToMaintenance: (() -> Void)?     = nil

    @State private var showMenu    = false
    @State private var showGrocery = false
    @State private var showPaywall = false

    // Warm palette
    private let amber   = Color(hex: "#C8922A") ?? .clear
    private let amberBg = Color(hex: "#F5E4C3") ?? .clear
    private let brown   = Color(hex: "#1A1208") ?? .clear
    private let muted   = Color(hex: "#7A6A55") ?? .clear
    private let divider = Color(hex: "#E6DDD0") ?? .clear
    private let cream   = Color(hex: "#FAF7F2") ?? .clear

    private var currentUserID: String {
        authVM.profile?.id.uuidString ?? authVM.userID?.uuidString ?? ""
    }
    private var currentMemberRole: HouseholdRole? {
        householdService.household?.members.first { $0.id == currentUserID }?.role
    }
    private var canSeeTrial: Bool {
        authVM.isOwner
    }

    // First name derived from the Supabase profile
    private var firstName: String {
        let full = authVM.profile?.fullName ?? ""
        return full.components(separatedBy: " ").first ?? "there"
    }

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()
            VStack(spacing: 0) {
                // ── Hero header + calendar strip (fixed) ──
                heroHeader

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        summaryGrid
                            .padding(.horizontal, 18)
                            .padding(.top, 20)

                        if authVM.trialDaysRemaining > 0 && canSeeTrial {
                            trialBanner.padding(.horizontal, 18)
                        }

                        upcomingEventsSection.padding(.horizontal, 18)
                        grocerySection.padding(.horizontal, 18)
                        maintenanceSection.padding(.horizontal, 18)
                    }
                    .padding(.bottom, 40)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { maintenanceVM.seedDefaultsIfNeeded() }
        .sheet(isPresented: $showMenu) {
            NavigationStack { SettingsView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGrocery) {
            GroceryListView(groceryVM: groceryVM)
        }
    }

    // MARK: - Hero Header
    private var heroHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Text(firstName)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.white)
                }
                Spacer()
                Button { showMenu = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 42, height: 42)
                        VStack(spacing: 5) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white)
                                    .frame(width: 18, height: 2)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            VStack(spacing: 6) {
                HStack {
                    Text(Date().monthYearDisplay)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                WarmMiniCalendarStrip(
                    scheduleVM: scheduleVM,
                    onDayTap: { date, _ in
                        onSwitchToSchedule?(date)
                    }
                )
                .padding(.bottom, 12)
            }
        }
        .background {
            LinearGradient(
                colors: [Color(hex: "#A0681A") ?? .clear, Color(hex: "#C8922A") ?? .clear, Color(hex: "#E6A83A") ?? .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
        }
        .overlay {
            Circle().fill(Color.white.opacity(0.06)).frame(width: 220).offset(x: 140, y: -40)
                .allowsHitTesting(false)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 140).offset(x: -60, y: 110)
                .allowsHitTesting(false)
        }

        .clipped()
    }

    // MARK: - Trial Banner
    private var trialBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.fill").foregroundColor(amber)
                Text("\(authVM.trialDaysRemaining) day\(authVM.trialDaysRemaining == 1 ? "" : "s") left in your trial")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(brown)
                Spacer()
                Text("Upgrade →").font(.system(size: 12, weight: .bold)).foregroundColor(amber)
            }
            .padding(14)
            .background(amberBg)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(amber.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Summary Grid
    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            WarmStatCard(
                value: "\(mealVM.todaysMeals.count) planned",
                label: "Today's Meals",
                icon: "fork.knife",
                color: Color(hex: "#E67E22") ?? .clear,
                action: { onSwitchToMeals?() }
            )
            WarmStatCard(
                value: "\(budgetVM.allUpcomingBills.count) bills",
                label: "Upcoming Bills",
                icon: "calendar.badge.exclamationmark",
                color: Color(hex: "#3949AB") ?? .clear,
                action: { onSwitchToBudget?() }
            )
            WarmStatCard(
                value: "\(scheduleVM.events(on: Date()).count) today",
                label: "Events Today",
                icon: "calendar",
                color: Color(hex: "#9C27B0") ?? .clear,
                action: { onSwitchToSchedule?(Date()) }
            )
            WarmStatCard(
                value: "\(maintenanceVM.dueSoonItems.count) due",
                label: "Maintenance",
                icon: "wrench.and.screwdriver.fill",
                color: Color(hex: "#C0392B") ?? .clear,
                action: { onSwitchToMaintenance?() }
            )
        }
    }

    // MARK: - Upcoming Events
    private var upcomingEventsSection: some View {
        WarmCard(
            title: "Upcoming Events",
            icon: "calendar",
            iconColor: Color(hex: "#9C27B0") ?? .clear,
            actionLabel: "Full Calendar",
            action: { onSwitchToSchedule?(Date()) }
        ) {
            if scheduleVM.upcomingEvents.isEmpty {
                WarmEmptyRow(icon: "calendar.badge.plus", message: "No upcoming events")
            } else {
                VStack(spacing: 0) {
                    ForEach(scheduleVM.upcomingEvents.prefix(4)) { event in
                        Button { onSwitchToSchedule?(event.date) } label: {
                            WarmEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        if event.id != scheduleVM.upcomingEvents.prefix(4).last?.id {
                            Color(hex: "#E6DDD0") ?? .clear.frame(height: 1).padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grocery
    private var grocerySection: some View {
        WarmCard(
            title: "Grocery Needs",
            icon: "cart.fill",
            iconColor: Color(hex: "#3D7A52") ?? .clear,
            actionLabel: groceryVM.uncheckedItems.isEmpty ? nil : "View List",
            action: { showGrocery = true }
        ) {
            if groceryVM.uncheckedItems.isEmpty {
                WarmEmptyRow(
                    icon: "checkmark.seal.fill",
                    message: "Pantry is stocked!",
                    color: Color(hex: "#3D7A52") ?? .clear
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(groceryVM.uncheckedItems.prefix(3)) { item in
                        Button { showGrocery = true } label: { WarmGroceryRow(item: item) }
                            .buttonStyle(.plain)
                        if item.id != groceryVM.uncheckedItems.prefix(3).last?.id {
                            Color(hex: "#E6DDD0") ?? .clear.frame(height: 1).padding(.vertical, 2)
                        }
                    }
                    if groceryVM.uncheckedItems.count > 3 {
                        Text("+ \(groceryVM.uncheckedItems.count - 3) more items")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#3D7A52") ?? .clear)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }

    // MARK: - Maintenance
    private var maintenanceSection: some View {
        WarmCard(
            title: "Maintenance Alerts",
            icon: "exclamationmark.triangle.fill",
            iconColor: Color(hex: "#C0392B") ?? .clear,
            actionLabel: (maintenanceVM.overdueItems.isEmpty && maintenanceVM.dueSoonItems.isEmpty) ? nil : "View All",
            action: { onSwitchToMaintenance?() }
        ) {
            let alerts = maintenanceVM.overdueItems + maintenanceVM.dueSoonItems
            if alerts.isEmpty {
                WarmEmptyRow(
                    icon: "checkmark.shield.fill",
                    message: "All maintenance up to date!",
                    color: Color(hex: "#3D7A52") ?? .clear
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(alerts.prefix(3)) { item in
                        Button { onSwitchToMaintenance?() } label: { WarmMaintenanceRow(item: item) }
                            .buttonStyle(.plain)
                        if item.id != alerts.prefix(3).last?.id {
                            Color(hex: "#E6DDD0") ?? .clear.frame(height: 1).padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<21: return "Good evening,"
        default:      return "Good night,"
        }
    }
}

// MARK: - Warm Mini Calendar Strip
struct WarmMiniCalendarStrip: View {
    @ObservedObject var scheduleVM: ScheduleViewModel
    let onDayTap: (Date, [CalendarEvent]) -> Void

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
                    let events     = scheduleVM.events(on: day)
                    let hasEvent   = !scheduleVM.events(on: day).isEmpty

                    Button {
                        selectedDate = day
                        onDayTap(day, events)
                    } label: {
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(isSelected ? 1.0 : 0.7))

                            ZStack {
                                Circle()
                                    .fill(isSelected
                                          ? Color.white
                                          : (isToday ? Color.white.opacity(0.25) : Color.clear))
                                    .frame(width: 34, height: 34)
                                Text(day.formatted(.dateTime.day()))
                                    .font(.system(size: 15,
                                                  weight: isToday || isSelected ? .bold : .regular))
                                    .foregroundColor(isSelected ? Color(hex: "#C8922A") ?? .clear : .white)
                            }

                            Circle()
                                .fill(hasEvent ? Color(hex: "#E53935") ?? .clear : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Warm Stat Card
struct WarmStatCard: View {
    let value:  String
    let label:  String
    let icon:   String
    let color:  Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(hex: "#1A1208") ?? .clear)
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
                }
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    Text("View").font(.system(size: 10, weight: .bold))
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(color)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.1)).cornerRadius(8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .background(Color.white)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "#E6DDD0") ?? .clear, lineWidth: 1))
            .shadow(color: Color(hex: "#1A1208") ?? .clear.opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Warm Card container
struct WarmCard<Content: View>: View {
    let title:       String
    let icon:        String
    let iconColor:   Color
    var actionLabel: String?
    var action:      (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconColor.opacity(0.12)).frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold)).foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
                    .kerning(0.3)
                Spacer()
                if let label = actionLabel, let action {
                    Button(action: action) {
                        HStack(spacing: 3) {
                            Text(label).font(.system(size: 11, weight: .bold))
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "#C8922A") ?? .clear)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(hex: "#F5E4C3") ?? .clear).cornerRadius(20)
                    }
                }
            }
            content()
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "#E6DDD0") ?? .clear, lineWidth: 1))
        .shadow(color: Color(hex: "#1A1208") ?? .clear.opacity(0.04), radius: 8, y: 3)
    }
}

// MARK: - Row components
struct WarmEventRow: View {
    let event: CalendarEvent
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: event.colorHex) ?? Color(hex: "#9C27B0") ?? .clear)
                    .frame(width: 4)
            }
            .frame(width: 4, height: 44)
            VStack(spacing: 1) {
                Text(event.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .heavy)).foregroundColor(Color(hex: "#7A6A55") ?? .clear)
                Text(event.date.formatted(.dateTime.day()))
                    .font(.system(size: 18, weight: .black)).foregroundColor(Color(hex: "#1A1208") ?? .clear)
            }
            .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1208") ?? .clear)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: event.category.iconName).font(.system(size: 9))
                    Text(event.isAllDay ? "All day" : event.formattedTime)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11)).foregroundColor(Color(hex: "#C5C0B8") ?? .clear)
        }
        .padding(.vertical, 6)
    }
}

struct WarmGroceryRow: View {
    let item: GroceryItem
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .stroke(Color(hex: "#E6DDD0") ?? .clear, lineWidth: 1.5)
                .frame(width: 18, height: 18)
            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "#1A1208") ?? .clear)
            Spacer()
            Text(item.displayQuantity)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
            Image(systemName: "chevron.right")
                .font(.system(size: 10)).foregroundColor(Color(hex: "#C5C0B8") ?? .clear)
        }
        .padding(.vertical, 6)
    }
}

struct WarmMaintenanceRow: View {
    let item: MaintenanceItem
    private var rowColor: Color {
        item.isOverdue ? Color(hex: "#C0392B") ?? .clear : Color(hex: "#E67E22") ?? .clear
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isOverdue ? "exclamationmark.circle.fill" : "clock.fill")
                .font(.system(size: 14)).foregroundColor(rowColor)
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "#1A1208") ?? .clear)
            Spacer()
            Text(item.statusLabel)
                .font(.system(size: 11, weight: .bold)).foregroundColor(rowColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(rowColor.opacity(0.1)).cornerRadius(20)
            Image(systemName: "chevron.right")
                .font(.system(size: 10)).foregroundColor(Color(hex: "#C5C0B8") ?? .clear)
        }
        .padding(.vertical, 6)
    }
}

struct WarmEmptyRow: View {
    let icon:    String
    let message: String
    var color:   Color = Color(hex: "#C8922A") ?? .clear
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(color.opacity(0.6))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Calendar Detail View
struct CalendarDetailView: View {
    let targetDate: Date
    @ObservedObject var scheduleVM: ScheduleViewModel
    @State private var selectedDate: Date

    init(targetDate: Date, scheduleVM: ScheduleViewModel) {
        self.targetDate = targetDate
        self.scheduleVM = scheduleVM
        _selectedDate   = State(initialValue: targetDate)
    }

    var body: some View {
        ZStack {
            Color(hex: "#FAF7F2") ?? .clear.ignoresSafeArea()
            VStack(spacing: 0) {
                CalendarStrip(selectedDate: $selectedDate, vm: scheduleVM)
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                ScrollView {
                    VStack(spacing: 16) {
                        CardView(
                            title: selectedDate.relativeLabel + " — Events",
                            icon: "calendar", iconColor: .purple,
                            actionLabel: "Add", action: {}
                        ) {
                            let dayEvents = scheduleVM.events(on: selectedDate)
                            if dayEvents.isEmpty {
                                InlineEmptyState(icon: "calendar.badge.plus",
                                                 message: "No events on this day.")
                            } else {
                                ForEach(dayEvents) { ev in
                                    EventDetailRow(
                                        event: ev,
                                        member: scheduleVM.member(for: ev.assignedToID),
                                        onDelete: { scheduleVM.deleteEvent(ev) }
                                    )
                                    if ev.id != dayEvents.last?.id { Divider() }
                                }
                            }
                        }
                        .padding(.horizontal)

                        CardView(
                            title: selectedDate.relativeLabel + " — Tasks",
                            icon: "checklist", iconColor: .blue
                        ) {
                            let dayTasks = scheduleVM.tasks(on: selectedDate)
                            if dayTasks.isEmpty {
                                InlineEmptyState(icon: "checkmark.circle",
                                                 message: "No tasks due on this day.")
                            } else {
                                ForEach(dayTasks) { task in
                                    TaskDetailRow(
                                        task: task,
                                        member: scheduleVM.member(for: task.assignedToID),
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
        .toolbarColorScheme(.light, for: .navigationBar)
        .tint(Color(hex: "#C8922A") ?? .clear)
    }
}

// MARK: - Legacy type aliases
typealias DashStatCard    = WarmStatCard
typealias DashboardCard   = WarmCard
typealias MiniCalendarStrip = WarmMiniCalendarStrip

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
        .environmentObject(HouseholdService.shared)
}
