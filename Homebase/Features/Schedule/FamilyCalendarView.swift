//  FamilyCalendarView.swift
//  HomeBase
//  Redesigned Schedule tab — reads real events from the iPhone's native Calendar
//  via EventKit and shows them alongside HomeBase tasks in a warm month grid.
//
//  SETUP (required):
//  In Info.plist add:
//    NSCalendarsUsageDescription               → "HomeBase shows your calendar events in the Schedule tab."
//    NSCalendarsFullAccessUsageDescription     → "HomeBase shows your calendar events in the Schedule tab."

internal import SwiftUI
internal import EventKit
internal import Combine

// MARK: - NativeCalendarService
@MainActor
final class NativeCalendarService: ObservableObject {

    @Published var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var nativeEvents: [EKEvent] = []

    private let store = EKEventStore()

    // MARK: - Request permission
    func requestAccess() async {
        let current = EKEventStore.authorizationStatus(for: .event)
        if current == .fullAccess {
            authStatus = current
            fetchEvents(for: Date())
            return
        }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authStatus  = EKEventStore.authorizationStatus(for: .event)
        if granted { fetchEvents(for: Date()) }
    }

    // MARK: - Fetch events for ±1 month around a date
    func fetchEvents(for date: Date) {
        guard isAuthorized else { return }
        let cal   = Calendar.current
        let start = cal.date(byAdding: .month, value: -1, to: cal.startOfDay(for: date)) ?? date
        let end   = cal.date(byAdding: .month, value:  2, to: start) ?? date
        let pred  = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        nativeEvents = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    }

    func events(on date: Date) -> [EKEvent] {
        let cal = Calendar.current
        return nativeEvents.filter { cal.isDate($0.startDate, inSameDayAs: date) }
    }

    func hasEvent(on date: Date) -> Bool { !events(on: date).isEmpty }

    var isAuthorized: Bool { authStatus == .fullAccess }
    var isDenied: Bool {
        authStatus == .denied || authStatus == .restricted
    }
}

// MARK: - FamilyCalendarView
struct FamilyCalendarView: View {

    @StateObject private var vm      = ScheduleViewModel()
    @StateObject private var calSvc  = NativeCalendarService()

    @State private var selectedDate  = Date()
    @State private var currentMonth  = Date()
    @State private var showAddEvent  = false
    @State private var showDelegate  = false

    // Warm palette
    private let amber   = Color(hex: "#C8922A")!
    private let amberBg = Color(hex: "#F5E4C3")!
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let divider = Color(hex: "#E6DDD0")!
    private let cream   = Color(hex: "#FAF7F2")!
    private let purple  = Color(hex: "#6A1B9A")!

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                cream.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    if calSvc.isDenied {
                        permissionBanner
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            monthGrid
                                .padding(.horizontal, 16)
                                .padding(.top, 14)

                            dayEventsSection
                                .padding(.horizontal, 20)
                                .padding(.top, 18)

                            dayTasksSection
                                .padding(.horizontal, 20)
                                .padding(.top, 14)

                            if !vm.overdueTasks.isEmpty {
                                overdueSection
                                    .padding(.horizontal, 20)
                                    .padding(.top, 14)
                            }

                            Spacer(minLength: 100)
                        }
                    }
                }

                addFAB
                    .padding(.trailing, 22)
                    .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .task { await calSvc.requestAccess() }
            .onChange(of: currentMonth) { _, m in calSvc.fetchEvents(for: m) }
            .sheet(isPresented: $showAddEvent) { AddEventView(vm: vm, preselectedDate: selectedDate) }
            .sheet(isPresented: $showDelegate) { TaskDelegationView(vm: vm) }
        }
    }

    // MARK: - Header
    private var headerBar: some View {
        ZStack {
            Color.white
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SCHEDULE")
                        .font(.system(size: 10, weight: .heavy)).kerning(3)
                        .foregroundColor(amber)
                    Text("My Calendar")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(brown)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35)) {
                        selectedDate = Date()
                        currentMonth = Date()
                    }
                } label: {
                    Text("Today")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(amber)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(amberBg)
                        .cornerRadius(20)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            .padding(.bottom, 14)
        }
        .frame(height: 120)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    // MARK: - Permission Banner
    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 20)).foregroundColor(amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar Access Needed")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(brown)
                Text("Allow access in Settings to see your iPhone Calendar events here.")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(muted)
            }
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Allow")
                    .font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(amber).cornerRadius(20)
            }
        }
        .padding(14)
        .background(amberBg)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    // MARK: - Month Grid
    private var monthGrid: some View {
        VStack(spacing: 0) {
            // Month navigator
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentMonth = Calendar.current.date(
                            byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(amber)
                        .frame(width: 32, height: 32).background(amberBg).clipShape(Circle())
                }
                Spacer()
                Text(currentMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 16, weight: .bold)).foregroundColor(brown)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentMonth = Calendar.current.date(
                            byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(amber)
                        .frame(width: 32, height: 32).background(amberBg).clipShape(Circle())
                }
            }
            .padding(.bottom, 12)

            // Weekday labels
            HStack(spacing: 0) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11, weight: .heavy)).foregroundColor(muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            // Day cells
            ForEach(calendarWeeks(for: currentMonth).indices, id: \.self) { wi in
                HStack(spacing: 0) {
                    ForEach(calendarWeeks(for: currentMonth)[wi].indices, id: \.self) { di in
                        dayCell(calendarWeeks(for: currentMonth)[wi][di])
                    }
                }
            }

            // Legend
            HStack(spacing: 14) {
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(purple).frame(width: 6, height: 6)
                    Text("iPhone Calendar")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(muted)
                }
                HStack(spacing: 4) {
                    Circle().fill(amber).frame(width: 6, height: 6)
                    Text("HomeBase")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(muted)
                }
            }
            .padding(.top, 8)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(divider, lineWidth: 1))
        .shadow(color: brown.opacity(0.05), radius: 10, y: 4)
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        let cal        = Calendar.current
        let isToday    = day.map { cal.isDateInToday($0) } ?? false
        let isSelected = day.map { cal.isDate($0, inSameDayAs: selectedDate) } ?? false
        let inMonth    = day.map { cal.isDate($0, equalTo: currentMonth, toGranularity: .month) } ?? false
        let hasNative  = day.map { calSvc.hasEvent(on: $0) } ?? false
        let hasHB      = day.map { vm.hasActivity(on: $0) } ?? false

        Button {
            if let d = day { withAnimation(.easeInOut(duration: 0.15)) { selectedDate = d } }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle().fill(amber).frame(width: 34, height: 34)
                    } else if isToday {
                        Circle().fill(amberBg).frame(width: 34, height: 34)
                    }
                    if let d = day {
                        Text("\(cal.component(.day, from: d))")
                            .font(.system(size: 14,
                                          weight: isSelected || isToday ? .bold : .regular))
                            .foregroundColor(
                                isSelected ? .white :
                                isToday    ? amber  :
                                inMonth    ? brown  : muted.opacity(0.35)
                            )
                    }
                }
                // Event dots
                HStack(spacing: 3) {
                    if hasNative { Circle().fill(purple).frame(width: 4, height: 4) }
                    if hasHB     { Circle().fill(amber).frame(width: 4, height: 4) }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
    }

    // MARK: - Day Events Section
    private var dayEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                warmIcon("calendar.circle.fill", color: purple)
                Text(selectedDate.isToday
                     ? "Today's Events"
                     : selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 15, weight: .bold)).foregroundColor(brown)
                    .lineLimit(1)
                Spacer()
                Button { showAddEvent = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(amber)
                        .frame(width: 28, height: 28).background(amberBg).clipShape(Circle())
                }
            }

            let native = calSvc.events(on: selectedDate)
            let hb     = vm.events(on: selectedDate)

            if native.isEmpty && hb.isEmpty {
                WarmEmptyLabel(icon: "calendar.badge.plus", text: "No events. Tap + to add.")
            } else {
                VStack(spacing: 0) {
                    ForEach(native, id: \.eventIdentifier) { ev in
                        NativeEventRow(event: ev)
                        divider.frame(height: 1).padding(.leading, 46)
                    }
                    ForEach(hb) { ev in
                        HBEventRow(event: ev,
                                   member: vm.member(for: ev.assignedToID),
                                   onDelete: { vm.deleteEvent(ev) })
                        if ev.id != hb.last?.id {
                            divider.frame(height: 1).padding(.leading, 46)
                        }
                    }
                }
                .background(Color.white)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(divider, lineWidth: 1))
                .shadow(color: brown.opacity(0.04), radius: 8, y: 3)
            }
        }
    }

    // MARK: - Day Tasks Section
    private var dayTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                warmIcon("checklist", color: amber)
                Text("Tasks").font(.system(size: 15, weight: .bold)).foregroundColor(brown)
                Spacer()
                Button { showDelegate = true } label: {
                    Text("Delegate")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(amber)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(amberBg).cornerRadius(20)
                }
            }

            let tasks = vm.tasks(on: selectedDate)
            if tasks.isEmpty {
                WarmEmptyLabel(icon: "checkmark.circle", text: "No tasks due on this day.")
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        CalendarTaskRow(
                            task:     task,
                            member:   vm.member(for: task.assignedToID),
                            onToggle: { vm.toggleTask(task) },
                            onDelete: { vm.deleteTask(task) }
                        )
                        if task.id != tasks.last?.id {
                            divider.frame(height: 1).padding(.leading, 56)
                        }
                    }
                }
                .background(Color.white)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(divider, lineWidth: 1))
                .shadow(color: brown.opacity(0.04), radius: 8, y: 3)
            }
        }
    }

    // MARK: - Overdue
    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                warmIcon("exclamationmark.circle.fill", color: Color(hex: "#C0392B")!)
                Text("Overdue").font(.system(size: 15, weight: .bold)).foregroundColor(brown)
            }
            VStack(spacing: 0) {
                ForEach(Array(vm.overdueTasks.prefix(3).enumerated()), id: \.element.id) { idx, task in
                    CalendarTaskRow(
                        task:     task,
                        member:   vm.member(for: task.assignedToID),
                        onToggle: { vm.toggleTask(task) },
                        onDelete: { vm.deleteTask(task) }
                    )
                    if idx < min(vm.overdueTasks.count, 3) - 1 {
                        divider.frame(height: 1).padding(.leading, 56)
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#C0392B")!.opacity(0.2), lineWidth: 1))
            .shadow(color: brown.opacity(0.04), radius: 8, y: 3)
        }
    }

    // MARK: - FAB
    private var addFAB: some View {
        Menu {
            Button { showAddEvent = true }  label: { Label("Add Event",      systemImage: "calendar.badge.plus") }
            Button { showDelegate = true }  label: { Label("Delegate Task",  systemImage: "person.badge.plus") }
        } label: {
            Circle()
                .fill(amber)
                .frame(width: 56, height: 56)
                .shadow(color: amber.opacity(0.4), radius: 14, y: 5)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                )
        }
    }

    // MARK: - Helpers
    private func warmIcon(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(0.12))
                .frame(width: 28, height: 28)
            Image(systemName: name)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
        }
    }

    private func calendarWeeks(for month: Date) -> [[Date?]] {
        let cal        = Calendar.current
        let first      = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let weekday    = cal.component(.weekday, from: first) - 1
        let daysCount  = cal.range(of: .day, in: .month, for: first)!.count
        var days: [Date?] = Array(repeating: nil, count: weekday)
        for i in 0..<daysCount {
            days.append(cal.date(byAdding: .day, value: i, to: first))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0+7]) }
    }
}

// MARK: - NativeEventRow
struct NativeEventRow: View {
    let event: EKEvent

    private var calColor: Color {
        Color(cgColor: event.calendar.cgColor)
    }
    private var timeLabel: String {
        event.isAllDay ? "All Day" : event.startDate.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(calColor)
                .frame(width: 4, height: 38)
                .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1208")!)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(timeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#7A6A55")!)
                    if let title = event.calendar?.title {
                        Text("· \(title)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#7A6A55")!).lineLimit(1)
                    }
                }
            }
            .padding(.leading, 10)

            Spacer()

            Text("iPhone")
                .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                .foregroundColor(calColor)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(calColor.opacity(0.1))
                .cornerRadius(20)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - HBEventRow
struct HBEventRow: View {
    let event:    CalendarEvent
    let member:   HouseholdMember?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.colorHex) ?? Color(hex: "#C8922A")!)
                .frame(width: 4, height: 38)
                .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1208")!)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(event.formattedTime)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#7A6A55")!)
                    if let m = member {
                        Text("· \(m.name)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#7A6A55")!)
                    }
                }
            }
            .padding(.leading, 10)

            Spacer()
        }
        .padding(.vertical, 10)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - WarmEmptyLabel
struct WarmEmptyLabel: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "#C8922A")!.opacity(0.5))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "#7A6A55")!)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#F5E4C3")!.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - CalendarDayCell
struct CalendarDayCell: View {
    let day:            Date?
    let isSelected:     Bool
    let isToday:        Bool
    let isCurrentMonth: Bool
    let hasHB:          Bool
    let hasNative:      Bool
    let onTap:          () -> Void

    private let amber  = Color(hex: "#C8922A")!
    private let purple = Color(hex: "#6A1B9A")!

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                if let day {
                    ZStack {
                        if isSelected {
                            Circle().fill(amber).frame(width: 32, height: 32)
                        } else if isToday {
                            Circle().stroke(amber, lineWidth: 1.5).frame(width: 32, height: 32)
                        }
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 14, weight: isSelected || isToday ? .bold : .regular))
                            .foregroundColor(
                                isSelected      ? .white :
                                isToday         ? amber :
                                !isCurrentMonth ? Color(hex: "#C5C0B8")! :
                                                  Color(hex: "#1A1208")!
                            )
                    }
                    .frame(width: 32, height: 32)

                    HStack(spacing: 3) {
                        if hasNative { Circle().fill(isSelected ? .white : purple).frame(width: 4, height: 4) }
                        if hasHB     { Circle().fill(isSelected ? .white : amber).frame(width: 4, height: 4) }
                        if !hasNative && !hasHB { Circle().fill(Color.clear).frame(width: 4, height: 4) }
                    }
                    .frame(height: 5)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                    Color.clear.frame(height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
    }
}

// MARK: - CalendarTaskRow
struct CalendarTaskRow: View {
    let task:     HouseTask
    let member:   HouseholdMember?
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var priorityColor: Color {
        switch task.priority {
        case .high:   return Color(hex: "#C0392B")!
        case .medium: return Color(hex: "#E67E22")!
        case .low:    return Color(hex: "#3D7A52")!
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { onToggle() } label: {
                ZStack {
                    Circle()
                        .stroke(task.isComplete ? Color(hex: "#3D7A52")! : Color(hex: "#E6DDD0")!, lineWidth: 2)
                        .frame(width: 26, height: 26)
                    if task.isComplete {
                        Circle().fill(Color(hex: "#3D7A52")!).frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white)
                    }
                }
                .animation(.spring(response: 0.25), value: task.isComplete)
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 14, weight: .bold))
                    .strikethrough(task.isComplete, color: Color(hex: "#7A6A55")!)
                    .foregroundColor(task.isComplete ? Color(hex: "#7A6A55")! : Color(hex: "#1A1208")!)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(task.priority.label)
                        .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                        .foregroundColor(priorityColor)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(priorityColor.opacity(0.1))
                        .cornerRadius(20)
                    if let m = member {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill").font(.system(size: 8))
                            Text(m.name).font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "#7A6A55")!)
                    }
                    if task.isOverdue {
                        Text("OVERDUE")
                            .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                            .foregroundColor(.red)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(20)
                    }
                }
            }

            Spacer()

            Button { onDelete() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Compatibility stubs
struct CalendarStrip: View {
    @Binding var selectedDate: Date
    @ObservedObject var vm: ScheduleViewModel
    var body: some View { EmptyView() }
}
struct EventDetailRow: View {
    let event: CalendarEvent; let member: HouseholdMember?; let onDelete: () -> Void
    var body: some View { HBEventRow(event: event, member: member, onDelete: onDelete) }
}
struct TaskDetailRow: View {
    let task: HouseTask; let member: HouseholdMember?
    let onToggle: () -> Void; let onDelete: () -> Void
    var body: some View {
        CalendarTaskRow(task: task, member: member, onToggle: onToggle, onDelete: onDelete)
    }
}

// Extension for isToday convenience — defined in Date_Helpers.swift
