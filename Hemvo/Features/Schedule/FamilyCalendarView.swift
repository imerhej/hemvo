//  FamilyCalendarView.swift
//  Hemvo
//  Replicates the iPhone Calendar app: month grid → week strip + day timeline.
//
//  Info.plist keys required:
//    NSCalendarsUsageDescription
//    NSCalendarsFullAccessUsageDescription

internal import SwiftUI
internal import EventKit
internal import Combine
internal import UserNotifications

// MARK: - NativeCalendarService
@MainActor
final class NativeCalendarService: ObservableObject {

    @Published var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var nativeEvents: [EKEvent] = []
    @Published var calendars:    [EKCalendar] = []

    private let store = EKEventStore()

    func checkExistingAccess() {
        authStatus = EKEventStore.authorizationStatus(for: .event)
        if authStatus == .fullAccess {
            loadCalendars()
            fetchEvents(for: Date())
        }
    }

    func requestAccess() async {
        let current = EKEventStore.authorizationStatus(for: .event)
        if current == .fullAccess {
            authStatus = current
            loadCalendars()
            fetchEvents(for: Date())
            return
        }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authStatus = EKEventStore.authorizationStatus(for: .event)
        if granted { loadCalendars(); fetchEvents(for: Date()) }
    }

    func loadCalendars() {
        calendars = store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    func fetchEvents(for date: Date) {
        guard isAuthorized else { return }
        let cal   = Calendar.current
        let start = cal.date(byAdding: .month, value: -2, to: cal.startOfDay(for: date)) ?? date
        let end   = cal.date(byAdding: .month, value:  3, to: start) ?? date
        let pred  = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        nativeEvents = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    }

    func events(on date: Date) -> [EKEvent] {
        let cal      = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart)!
        return nativeEvents.filter { ev in
            ev.startDate < dayEnd && ev.endDate > dayStart
        }
    }

    func hasEvent(on date: Date) -> Bool { !events(on: date).isEmpty }

    var isAuthorized: Bool { authStatus == .fullAccess }
    var isDenied: Bool     { authStatus == .denied || authStatus == .restricted }
}

// MARK: - FamilyCalendarView
struct FamilyCalendarView: View {

    @Binding var jumpToDate: Date?

    init(jumpToDate: Binding<Date?> = .constant(nil)) {
        self._jumpToDate = jumpToDate
    }

    @StateObject private var vm     = ScheduleViewModel()
    @StateObject private var calSvc = NativeCalendarService()
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var householdService: HouseholdService

    private var canWrite: Bool {
        guard let uid = authVM.userID?.uuidString,
              let member = householdService.household?.members.first(where: { $0.id == uid })
        else { return true }
        return member.role.canWrite
    }

    // Navigation state
    enum CalMode { case year, month, week }
    @State private var mode:          CalMode = .month
    @State private var selectedDate   = Date()
    @State private var displayedMonth = Date()
    @State private var displayedYear  = Calendar.current.component(.year, from: Date())

    // Sheet state
    @State private var showAddEvent    = false
    @State private var showCalendars   = false
    @State private var showSearch      = false
    @State private var searchQuery     = ""
    @FocusState private var searchFocused: Bool

    // Edit/delete HB events
    @State private var eventToEdit:    CalendarEvent? = nil
    @State private var eventToDelete:  CalendarEvent? = nil
    @State private var eventToView:    CalendarEvent? = nil
    @State private var showDeleteAlert = false
    @State private var monthScrollID: Date? = {
        let c = Calendar.current
        return c.date(from: c.dateComponents([.year, .month], from: Date()))
    }()

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    topBar
                    calendarAccessBanner
                    if mode == .year  { yearView  }
                    else if mode == .month { monthView }
                    else { weekDayView }
                }
                .background(Color(.systemBackground).ignoresSafeArea())

                // Floating add button — owners and adults only
                if !showSearch && canWrite {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button { showAddEvent = true } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "calendar.badge.plus")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Add Event")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 11)
                                .padding(.horizontal, 18)
                                .background(Color.systemRed)
                                .clipShape(Capsule())
                                .shadow(color: Color.systemRed.opacity(0.4), radius: 8, y: 3)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 16)
                        }
                    }
                    .zIndex(5)
                }

                if showSearch {
                    searchOverlay.transition(.opacity).zIndex(10)
                }
            }
            .task { calSvc.checkExistingAccess() }
            .onAppear {
                // Handle the case where jumpToDate is already set when the view is first created
                // (e.g. tapping an event from the dashboard before the schedule tab is active)
                if let d = jumpToDate {
                    let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: d))
                    selectedDate   = d
                    displayedMonth = monthStart ?? d
                    monthScrollID  = monthStart
                    mode           = .month
                    jumpToDate     = nil
                }
            }
            .onChange(of: jumpToDate) { _, newDate in
                guard let d = newDate else { return }
                let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: d))
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedDate   = d
                    displayedMonth = monthStart ?? d
                    monthScrollID  = monthStart
                    mode           = .month
                }
                jumpToDate = nil
            }
            .sheet(isPresented: $showAddEvent) {
                NativeAddEventSheet(store: calSvc, preselectedDate: selectedDate) { event, cat, repeatRule, travelTime, alertOption, colorHex, location, inviteeIDs, scope in
                    calSvc.fetchEvents(for: selectedDate)
                    let hbEvent = CalendarEvent(
                        title:       event.title ?? "",
                        location:    location,
                        date:        event.startDate,
                        endDate:     event.endDate,
                        isAllDay:    event.isAllDay,
                        notes:       event.notes ?? "",
                        category:    cat,
                        colorHex:    colorHex,
                        repeatRule:  repeatRule,
                        travelTime:  travelTime,
                        alertOption: alertOption,
                        inviteeIDs:  inviteeIDs,
                        scope:       scope
                    )
                    vm.addEvent(hbEvent)
                }
            }
            .sheet(isPresented: $showCalendars) {
                CalendarsSheet(calSvc: calSvc)
            }
            .sheet(item: $eventToEdit) { ev in
                EditCalendarEventSheet(event: ev, vm: vm)
            }
            .sheet(item: $eventToView) { ev in
                EventDetailSheet(event: ev,
                    assignedMember: vm.member(for: ev.assignedToID),
                    onEdit:    { eventToEdit = ev },
                    onDelete:  { eventToDelete = ev; showDeleteAlert = true },
                    canDelete: vm.canDelete(ev),
                    canEdit:   canWrite && vm.canEdit(ev))
            }
            .alert("Delete Event", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let ev = eventToDelete { vm.deleteEvent(ev) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Remove \"\(eventToDelete?.title ?? "this event")\"?")
            }
        }
    }

    // MARK: - Calendar access banner
    @ViewBuilder
    private var calendarAccessBanner: some View {
        if calSvc.isDenied {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                Text("Calendar access denied.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.systemRed)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
        } else if calSvc.authStatus == .notDetermined {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.systemRed)
                Text("Connect Apple Calendar to see your events here.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Connect") {
                    Task { await calSvc.requestAccess() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.systemRed)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
        }
    }

    // MARK: - Top toolbar
    private var topBar: some View {
        HStack(spacing: 8) {
            // Back / year button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    switch mode {
                    case .week:
                        mode = .month
                    case .month:
                        displayedYear = cal.component(.year, from: displayedMonth)
                        mode = .year
                    case .year:
                        displayedYear = max(displayedYear - 1, 1970)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text(mode == .week
                         ? displayedMonth.formatted(.dateTime.month(.wide))
                         : mode == .month
                           ? String(cal.component(.year, from: displayedMonth))
                           : String(displayedYear))
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.systemRed)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Color(.systemGray6))
                .cornerRadius(20)
            }

            // Today button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    let today = Date()
                    selectedDate    = today
                    displayedMonth  = today
                    displayedYear   = cal.component(.year, from: today)
                    monthScrollID   = cal.date(from: cal.dateComponents([.year, .month], from: today))
                    if mode == .year { mode = .month }
                }
            } label: {
                Text("Today")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.systemRed)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
            }

            Spacer()

            HStack(spacing: 10) {
                // Grid toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = (mode == .month) ? .week : .month
                    }
                } label: {
                    Image(systemName: mode == .week ? "square.grid.2x2" : "rectangle.grid.1x2")
                        .font(.system(size: 17))
                        .foregroundColor(.systemRed)
                        .frame(width: 40, height: 40)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }

                // Search
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { searchQuery = ""; showSearch = true }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17))
                        .foregroundColor(.systemRed)
                        .frame(width: 40, height: 40)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }

            }
            .padding(.trailing, 14)
        }
        .padding(.leading, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Year View (12 mini months in a 3×4 grid)
    private var yearView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Year title + prev/next nav
                HStack {
                    Text(String(displayedYear))
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.primary)
                    Spacer()
                    HStack(spacing: 6) {
                        Button {
                            withAnimation { displayedYear = max(displayedYear - 1, 1970) }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.systemRed)
                                .frame(width: 34, height: 34)
                                .background(Color(.systemGray6))
                                .clipShape(Circle())
                        }
                        Button {
                            withAnimation { displayedYear += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.systemRed)
                                .frame(width: 34, height: 34)
                                .background(Color(.systemGray6))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)

                // 3-column grid of mini months
                let months = (1...12).compactMap { m -> Date? in
                    cal.date(from: DateComponents(year: displayedYear, month: m, day: 1))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 20) {
                    ForEach(months, id: \.self) { monthDate in
                        miniMonthCard(monthDate)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func miniMonthCard(_ monthDate: Date) -> some View {
        let monthIndex = cal.component(.month, from: monthDate)
        // Palette: each month gets a distinct accent
        let monthColors: [Color] = [
            Color(hex: "#E53935") ?? .clear, // Jan - red
            Color(hex: "#E91E63") ?? .clear, // Feb - pink
            Color(hex: "#9C27B0") ?? .clear, // Mar - purple
            Color(hex: "#3F51B5") ?? .clear, // Apr - indigo
            Color(hex: "#2196F3") ?? .clear, // May - blue
            Color(hex: "#00BCD4") ?? .clear, // Jun - cyan
            Color(hex: "#009688") ?? .clear, // Jul - teal
            Color(hex: "#4CAF50") ?? .clear, // Aug - green
            Color(hex: "#8BC34A") ?? .clear, // Sep - light green
            Color(hex: "#FF9800") ?? .clear, // Oct - orange
            Color(hex: "#FF5722") ?? .clear, // Nov - deep orange
            Color(hex: "#795548") ?? .clear, // Dec - brown
        ]
        let accent = monthColors[monthIndex - 1]
        let isCurrentMonth = cal.isDate(monthDate, equalTo: Date(), toGranularity: .month)

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = monthDate
                monthScrollID  = cal.date(from: cal.dateComponents([.year, .month], from: monthDate))
                mode = .month
            }
        } label: {
            VStack(spacing: 5) {
                // Month header
                HStack {
                    Text(monthDate.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isCurrentMonth ? accent : .primary)
                    Spacer()
                    if isCurrentMonth {
                        Circle().fill(accent).frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // Weekday labels
                HStack(spacing: 0) {
                    ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                        Text(d)
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4)

                // Day cells
                let weeks = calendarWeeks(for: monthDate)
                VStack(spacing: 1) {
                    ForEach(weeks.indices, id: \.self) { wi in
                        HStack(spacing: 0) {
                            ForEach(weeks[wi].indices, id: \.self) { di in
                                if let day = weeks[wi][di] {
                                    let isToday   = cal.isDateInToday(day)
                                    let hasEvents = calSvc.hasEvent(on: day) || vm.hasActivity(on: day)
                                    ZStack {
                                        if isToday {
                                            Circle().fill(accent).frame(width: 18, height: 18)
                                        }
                                        Text("\(cal.component(.day, from: day))")
                                            .font(.system(size: 8, weight: isToday ? .bold : .regular))
                                            .foregroundColor(isToday ? .white : .primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .overlay(alignment: .bottom) {
                                        if hasEvents && !isToday {
                                            Circle().fill(accent).frame(width: 3, height: 3)
                                                .offset(y: 1)
                                        }
                                    }
                                } else {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .frame(height: 16)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrentMonth ? accent.opacity(0.5) : Color(.systemGray5), lineWidth: isCurrentMonth ? 1.5 : 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Month View
    private var monthView: some View {
        VStack(spacing: 0) {
            // Month title — updates as user scrolls
            HStack {
                Text(displayedMonth.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.primary)
                    .padding(.leading, 16)
                    .padding(.top, 2)
                Spacer()
            }

            weekdayHeader

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(monthPages, id: \.self) { month in
                            monthGridView(for: month)
                                .id(month)
                        }
                    }
                    .scrollTargetLayout()
                }
                .frame(maxHeight: .infinity)
                .scrollPosition(id: $monthScrollID, anchor: .top)
                .onChange(of: monthScrollID) { _, newID in
                    if let d = newID {
                        displayedMonth = d
                        calSvc.fetchEvents(for: d)
                    }
                }
                .onAppear {
                    // Re-anchor on first mount / mode switch.
                    if let id = monthScrollID {
                        DispatchQueue.main.async {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
                // LazyVStack loses its position while a sheet covers it, causing the
                // two-way scrollPosition binding to overwrite monthScrollID with a
                // wrong month on dismiss.  Re-anchor after the sheet animation finishes.
                .onChange(of: showAddEvent)  { _, showing in reanchorIfNeeded(showing, proxy: proxy) }
                .onChange(of: showCalendars) { _, showing in reanchorIfNeeded(showing, proxy: proxy) }
                .onChange(of: eventToEdit)   { _, ev     in if ev == nil { reanchorScroll(proxy: proxy) } }
                .onChange(of: eventToView)   { _, ev     in if ev == nil { reanchorScroll(proxy: proxy) } }
            }
        }
    }

    private var monthPages: [Date] {
        let base = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        return (-48...48).compactMap { cal.date(byAdding: .month, value: $0, to: base) }
    }

    // MARK: - Weekday header row
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                Text(d)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(.systemGray2))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Month grid
    private func monthGridView(for month: Date) -> some View {
        let weeks = calendarWeeks(for: month)
        return VStack(spacing: 0) {
            ForEach(weeks.indices, id: \.self) { wi in
                HStack(spacing: 0) {
                    ForEach(weeks[wi].indices, id: \.self) { di in
                        monthDayCell(weeks[wi][di], inMonth: month)
                    }
                }
                .frame(minHeight: 96)
                Divider()
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func monthDayCell(_ day: Date?, inMonth month: Date) -> some View {
        let isToday    = day.map { cal.isDateInToday($0) } ?? false
        let isSelected = day.map { cal.isDate($0, inSameDayAs: selectedDate) } ?? false
        let inMonth    = day.map { cal.isDate($0, equalTo: month, toGranularity: .month) } ?? false
        let events     = day.map { calSvc.events(on: $0) } ?? []
        let hbEvents   = day.map { vm.events(on: $0) } ?? []
        let isSun = day.map { cal.component(.weekday, from: $0) == 1 } ?? false
        let isSat = day.map { cal.component(.weekday, from: $0) == 7 } ?? false
        let allEvents  = events.count + hbEvents.count
        let maxPills   = 3

        VStack(alignment: .leading, spacing: 3) {
            // Day number — tap to select
            HStack {
                Button {
                    if let d = day {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedDate = d }
                    }
                } label: {
                    ZStack {
                        if isToday {
                            Circle().fill(Color.systemRed).frame(width: 32, height: 32)
                        } else if isSelected {
                            Circle().fill(Color(.systemGray4)).frame(width: 32, height: 32)
                        }
                        if let d = day {
                            Text("\(cal.component(.day, from: d))")
                                .font(.system(size: 16, weight: isToday ? .bold : .semibold))
                                .foregroundColor(
                                    isToday          ? .white :
                                    !inMonth         ? Color(.systemGray4) :
                                    (isSun || isSat) ? Color(.systemGray2) :
                                    .primary
                                )
                        }
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 6)
            .padding(.leading, 4)

            // Event pills — scrollable when > maxPills events
            if allEvents > maxPills {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(events, id: \.eventIdentifier) { ev in
                            eventPill(title: ev.title ?? "",
                                      color: Color(cgColor: ev.calendar.cgColor),
                                      isAllDay: ev.isAllDay)
                        }
                        ForEach(hbEvents, id: \.id) { ev in
                            Button { eventToView = ev } label: {
                                eventPill(title: ev.title,
                                          color: Color(hex: ev.colorHex) ?? .purple,
                                          isAllDay: ev.isAllDay,
                                          icon: ev.category.iconName)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 60)
                .padding(.horizontal, 1)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(events, id: \.eventIdentifier) { ev in
                        eventPill(title: ev.title ?? "",
                                  color: Color(cgColor: ev.calendar.cgColor),
                                  isAllDay: ev.isAllDay)
                    }
                    let remaining = max(0, maxPills - events.count)
                    ForEach(hbEvents.prefix(remaining), id: \.id) { ev in
                        Button { eventToView = ev } label: {
                            eventPill(title: ev.title,
                                      color: Color(hex: ev.colorHex) ?? .purple,
                                      isAllDay: ev.isAllDay,
                                      icon: ev.category.iconName)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .disabled(day == nil)
    }

    private func eventPill(title: String, color: Color, isAllDay: Bool, icon: String? = nil) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundColor(color)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }

    // MARK: - Selected day events list
    private var selectedDayEventsList: some View {
        let events    = calSvc.events(on: selectedDate).sorted { $0.startDate < $1.startDate }
        let hbEvs     = vm.events(on: selectedDate).sorted { $0.date < $1.date }
        let tasks     = vm.tasks(on: selectedDate)
        let dateLabel = selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(dateLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if events.isEmpty && hbEvs.isEmpty && tasks.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar").foregroundColor(.secondary)
                        Text("No events").font(.system(size: 14)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                } else {
                    // Native EKEvents (read-only, no edit — they live in Apple Calendar)
                    ForEach(events, id: \.eventIdentifier) { ev in
                        dayListEventRow(
                            title: ev.title ?? "Untitled",
                            time:  ev.isAllDay ? "all-day" : ev.startDate.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)),
                            color: Color(cgColor: ev.calendar.cgColor),
                            cal:   ev.calendar?.title ?? "",
                            onEdit:   nil,
                            onDelete: nil
                        )
                        Divider().padding(.leading, 16)
                    }

                    // Hemvo events — tappable; editable & deletable for owners/adults only
                    ForEach(hbEvs, id: \.id) { ev in
                        Button { eventToView = ev } label: {
                            dayListEventRow(
                                title:    ev.title,
                                time:     ev.formattedTime,
                                color:    Color(hex: ev.colorHex) ?? .purple,
                                cal:      ev.category.rawValue,
                                onEdit:   (canWrite && vm.canEdit(ev)) ? { eventToEdit = ev } : nil,
                                onDelete: (canWrite && vm.canDelete(ev)) ? { eventToDelete = ev; showDeleteAlert = true } : nil
                            )
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }

                    // Tasks
                    ForEach(tasks, id: \.id) { task in
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(task.priority.displayColor)
                                .frame(width: 3).padding(.vertical, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(task.isComplete ? .secondary : .primary)
                                    .strikethrough(task.isComplete)
                                Text("Task · \(task.priority.label)")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            Spacer()
                            if canWrite {
                                Button { vm.toggleTask(task) } label: {
                                    Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(task.isComplete ? .green : Color(.systemGray3))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(task.isComplete ? .green : Color(.systemGray3))
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    private func dayListEventRow(
        title: String, time: String, color: Color, cal: String,
        onEdit: (() -> Void)?, onDelete: (() -> Void)?
    ) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(color).frame(width: 3).padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                HStack(spacing: 4) {
                    Text(time).font(.system(size: 12)).foregroundColor(.secondary)
                    if !cal.isEmpty {
                        Text("· \(cal)").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            // Edit / delete buttons for HB events
            if onEdit != nil || onDelete != nil {
                HStack(spacing: 8) {
                    if let onEdit {
                        Button { onEdit() } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.systemRed)
                                .frame(width: 28, height: 28)
                                .background(Color.systemRed.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let onDelete {
                        Button { onDelete() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(width: 28, height: 28)
                                .background(Color.red.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Search overlay
    private var searchOverlay: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search events…", text: $searchQuery)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($searchFocused)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    Button("Cancel") {
                        withAnimation { showSearch = false; searchQuery = "" }
                    }
                    .foregroundColor(.systemRed)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 12)

                Divider()

                // Results
                let results = searchResults
                if searchQuery.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40)).foregroundColor(.secondary)
                        Text("Type to search events")
                            .font(.system(size: 15)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 40)).foregroundColor(.secondary)
                        Text("No events found for \"\(searchQuery)\"")
                            .font(.system(size: 15)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results, id: \.id) { item in
                        Button {
                            if let ev = item.event {
                                withAnimation { showSearch = false }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    eventToView = ev
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Rectangle().fill(item.color).frame(width: 3, height: 40).cornerRadius(1.5)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(item.subtitle)
                                        .font(.system(size: 12)).foregroundColor(.secondary)
                                }
                                Spacer()
                                if item.event != nil {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .listStyle(.plain)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                searchFocused = true
            }
        }
    }

    private struct SearchResult: Identifiable {
        let id       = UUID()
        let title:    String
        let subtitle: String
        let color:    Color
        let event:    CalendarEvent?   // nil for native EK events
    }

    private var searchResults: [SearchResult] {
        let q = searchQuery.lowercased()
        guard !q.isEmpty else { return [] }
        var out: [SearchResult] = []
        for ev in vm.events where ev.title.lowercased().contains(q) {
            out.append(SearchResult(
                title:    ev.title,
                subtitle: ev.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · " + ev.formattedTime,
                color:    Color(hex: ev.colorHex) ?? .purple,
                event:    ev
            ))
        }
        for ev in calSvc.nativeEvents where (ev.title ?? "").lowercased().contains(q) {
            out.append(SearchResult(
                title:    ev.title ?? "",
                subtitle: ev.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                color:    Color(cgColor: ev.calendar.cgColor),
                event:    nil
            ))
        }
        return out
    }

    // MARK: - Week + Day Timeline View
    private var weekDayView: some View {
        VStack(spacing: 0) {
            weekStrip
            Divider()
            dayTimeline
        }
    }

    private var weekStrip: some View {
        let days = weekDays(for: selectedDate)
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isToday    = cal.isDateInToday(day)
                let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
                let hasEvents  = calSvc.hasEvent(on: day) || vm.hasActivity(on: day)
                let wd         = day.formatted(.dateTime.weekday(.abbreviated)).uppercased()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedDate = day }
                } label: {
                    VStack(spacing: 2) {
                        Text(String(wd.prefix(1)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isToday ? .systemRed : .secondary)

                        ZStack {
                            if isToday && isSelected {
                                Circle().fill(Color.systemRed).frame(width: 34, height: 34)
                            } else if isSelected {
                                Circle().fill(Color(.systemGray4)).frame(width: 34, height: 34)
                            }
                            Text("\(cal.component(.day, from: day))")
                                .font(.system(size: 17, weight: isToday ? .bold : .semibold))
                                .foregroundColor(
                                    (isToday && isSelected) ? .white :
                                    isToday ? .systemRed : .primary
                                )
                        }

                        // Event dot
                        Circle()
                            .fill(hasEvents ? (isToday ? Color.systemRed : Color(.systemGray3)) : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dayTimeline: some View {
        let events    = calSvc.events(on: selectedDate)
        let allDayEvs = events.filter { $0.isAllDay }
        let timedEvs  = events.filter { !$0.isAllDay }
        let hbEvs     = vm.events(on: selectedDate)
        let title     = selectedDate.formatted(.dateTime.weekday(.wide)) + " – " +
                        selectedDate.formatted(.dateTime.month(.abbreviated).day(.defaultDigits)) + ", " +
                        selectedDate.formatted(.dateTime.year())

        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Date title
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                    // All-day row
                    if !allDayEvs.isEmpty || !hbEvs.filter({ $0.isAllDay }).isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text("all-day")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 52, alignment: .trailing)
                            VStack(spacing: 4) {
                                ForEach(allDayEvs, id: \.eventIdentifier) { ev in
                                    allDayChip(title: ev.title ?? "", color: Color(cgColor: ev.calendar.cgColor))
                                }
                                ForEach(hbEvs.filter { $0.isAllDay }, id: \.id) { ev in
                                    allDayChip(title: ev.title, color: Color(hex: ev.colorHex) ?? .purple)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        Divider()
                    }

                    // Hourly timeline
                    ZStack(alignment: .topLeading) {
                        // Hour lines
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                HStack(alignment: .top, spacing: 0) {
                                    Text(hour == 0 ? "" : "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .frame(width: 52, alignment: .trailing)
                                        .padding(.trailing, 8)
                                        .offset(y: -7)
                                    Rectangle()
                                        .fill(Color(.systemGray5))
                                        .frame(height: 0.5)
                                }
                                .id(hour)
                                .frame(height: 52)
                            }
                        }

                        // Timed events overlay
                        ForEach(timedEvs, id: \.eventIdentifier) { ev in
                            timedEventBlock(ev)
                        }
                        ForEach(hbEvs.filter { !$0.isAllDay }, id: \.id) { ev in
                            hbEventBlock(ev)
                        }

                        // Current time line
                        if cal.isDateInToday(selectedDate) {
                            currentTimeLine
                        }
                    }
                }
            }
            .onAppear {
                let hour = cal.component(.hour, from: Date())
                proxy.scrollTo(max(hour - 1, 0), anchor: .top)
            }
        }
    }

    private func allDayChip(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Image(systemName: "person.2.fill")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color)
        .cornerRadius(6)
    }

    private func timedEventBlock(_ ev: EKEvent) -> some View {
        let color    = Color(cgColor: ev.calendar.cgColor)
        let startMin = minuteOfDay(ev.startDate)
        let durMin   = max(minuteOfDay(ev.endDate) - startMin, 30)
        let top      = CGFloat(startMin) / 60.0 * 52.0
        let height   = CGFloat(durMin)  / 60.0 * 52.0

        return HStack(spacing: 0) {
            Spacer().frame(width: 60)
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.2))
                .overlay(
                    HStack(alignment: .top) {
                        Rectangle().fill(color).frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.title ?? "")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(color)
                                .lineLimit(2)
                            Text(ev.startDate.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                                .font(.system(size: 10))
                                .foregroundColor(color.opacity(0.8))
                        }
                        .padding(4)
                        Spacer()
                    }
                )
                .frame(height: max(height, 30))
                .padding(.trailing, 8)
        }
        .offset(y: top)
        .frame(height: max(height, 30))
        .allowsHitTesting(false)
    }

    private func hbEventBlock(_ ev: CalendarEvent) -> some View {
        let color    = Color(hex: ev.colorHex) ?? .purple
        let startMin = minuteOfDay(ev.date)
        let endMin   = ev.endDate.map { minuteOfDay($0) } ?? (startMin + 60)
        let durMin   = max(endMin - startMin, 30)
        let top      = CGFloat(startMin) / 60.0 * 52.0
        let height   = CGFloat(durMin)  / 60.0 * 52.0

        return HStack(spacing: 0) {
            Spacer().frame(width: 60)
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.15))
                .overlay(
                    HStack(alignment: .top) {
                        Rectangle().fill(color).frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(color)
                                .lineLimit(2)
                            Text(ev.formattedTime)
                                .font(.system(size: 10))
                                .foregroundColor(color.opacity(0.8))
                        }
                        .padding(4)
                        Spacer()
                    }
                )
                .frame(height: max(height, 30))
                .padding(.trailing, 8)
        }
        .offset(y: top)
        .frame(height: max(height, 30))
        .allowsHitTesting(false)
    }

    private var currentTimeLine: some View {
        let now = minuteOfDay(Date())
        return HStack(spacing: 0) {
            Text(Date().formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.systemRed)
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 8)
            Circle().fill(Color.systemRed).frame(width: 10, height: 10)
            Rectangle().fill(Color.systemRed).frame(height: 1)
        }
        .offset(y: CGFloat(now) / 60.0 * 52.0 - 5)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func reanchorIfNeeded(_ isShowing: Bool, proxy: ScrollViewProxy) {
        guard !isShowing else { return }
        reanchorScroll(proxy: proxy)
    }

    private func reanchorScroll(proxy: ScrollViewProxy) {
        guard let id = monthScrollID else { return }
        // Wait for the sheet-dismiss animation (~0.35 s) before scrolling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private func calendarWeeks(for month: Date) -> [[Date?]] {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let weekday = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let count   = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var days: [Date?] = Array(repeating: nil, count: weekday)
        for i in 0..<count { days.append(cal.date(byAdding: .day, value: i, to: first)) }
        while days.count % 7 != 0 { days.append(nil) }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0+7]) }
    }

    private func weekDays(for date: Date) -> [Date] {
        let sunday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: sunday) }
    }

    private func minuteOfDay(_ date: Date) -> Int {
        cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }
}

// MARK: - 12-hour wheel time picker (always shows H | MM | AM/PM regardless of device locale)
private struct TimeWheelPicker: View {
    @Binding var date: Date

    @State private var hour:   Int = 12
    @State private var minute: Int = 0
    @State private var period: Int = 0  // 0 = AM, 1 = PM

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: $hour) {
                ForEach(1...12, id: \.self) { h in Text("\(h)").tag(h) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            Picker("", selection: $minute) {
                ForEach(0...59, id: \.self) { m in Text(String(format: "%02d", m)).tag(m) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            Picker("", selection: $period) {
                Text("AM").tag(0)
                Text("PM").tag(1)
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: 180)
        .onAppear { load() }
        .onChange(of: hour)   { _, _ in save() }
        .onChange(of: minute) { _, _ in save() }
        .onChange(of: period) { _, _ in save() }
    }

    private func load() {
        let cal = Calendar.current
        let h   = cal.component(.hour, from: date)
        hour   = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        minute = cal.component(.minute, from: date)
        period = h < 12 ? 0 : 1
    }

    private func save() {
        var h24 = hour % 12          // 12 → 0, 1–11 unchanged
        if period == 1 { h24 += 12 } // PM → +12
        let cal = Calendar.current
        if let updated = cal.date(bySettingHour: h24, minute: minute, second: 0, of: date) {
            date = updated
        }
    }
}

// MARK: - Calendars Sheet (Image 3)
struct CalendarsSheet: View {
    @ObservedObject var calSvc: NativeCalendarService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                let grouped = Dictionary(grouping: calSvc.calendars) { $0.source.title }
                ForEach(grouped.keys.sorted(), id: \.self) { source in
                    Section(source) {
                        ForEach(grouped[source] ?? [], id: \.calendarIdentifier) { cal in
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color(cgColor: cal.cgColor))
                                        .frame(width: 22, height: 22)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cal.title)
                                        .font(.system(size: 16))
                                    if cal.type == .subscription {
                                        Text("Subscribed")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button { } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.systemRed)
                                        .font(.system(size: 20))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    Toggle("Show Declined Events", isOn: .constant(false))
                    Toggle("Show Completed Reminders", isOn: .constant(true))
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Shared color palette
private let eventColorPalette: [String] = [
    "#F44336", "#E91E63", "#9C27B0", "#673AB7",
    "#3F51B5", "#2196F3", "#03A9F4", "#00BCD4",
    "#009688", "#4CAF50", "#8BC34A", "#FFC107",
    "#FF9800", "#FF5722", "#795548", "#607D8B",
]

// MARK: - Native Add Event Sheet
struct NativeAddEventSheet: View {

    @ObservedObject var store: NativeCalendarService
    var preselectedDate: Date
    var onSave: (EKEvent, CalendarEvent.EventCategory, CalendarEvent.RecurrenceRule, String, String, String, String, [UUID], CalendarEvent.EventScope) -> Void

    @Environment(\.dismiss) var dismiss
    @FocusState private var titleFocused:    Bool
    @FocusState private var locationFocused: Bool
    @FocusState private var notesFocused:   Bool

    // Basic fields
    @State private var title            = ""
    @State private var location         = ""
    @State private var notes            = ""
    @State private var isAllDay         = false
    @State private var startDate: Date
    @State private var endDate:   Date
    @State private var category         = CalendarEvent.EventCategory.general
    @State private var selectedColorHex = CalendarEvent.EventCategory.general.defaultColorHex

    // Invitees
    @State private var inviteeIDs: Set<UUID> = []

    // Inline pickers
    @State private var showStartDatePicker = false
    @State private var showStartTimePicker = false
    @State private var showEndDatePicker   = false
    @State private var showEndTimePicker   = false
    @State private var showTravelPicker    = false
    @State private var showRepeatPicker = false
    @State private var showAlertPicker  = false

    // Picker values
    @State private var travelTime  = TravelOption.none
    @State private var repeatRule  = RepeatOption.never
    @State private var alertOption = AlertOption.none
    @State private var eventScope  = CalendarEvent.EventScope.personal

    // Travel options
    enum TravelOption: String, CaseIterable {
        case none    = "None"
        case five    = "5 minutes"
        case fifteen = "15 minutes"
        case thirty  = "30 minutes"
        case hour    = "1 hour"
        case ninety  = "1.5 hours"
        case two     = "2 hours"
    }

    // Repeat options
    enum RepeatOption: String, CaseIterable {
        case never    = "Never"
        case daily    = "Every Day"
        case weekly   = "Every Week"
        case biweekly = "Every 2 Weeks"
        case monthly  = "Every Month"
        case yearly   = "Every Year"
    }

    // Alert options
    enum AlertOption: String, CaseIterable {
        case none       = "None"
        case atTime     = "At time of event"
        case five       = "5 minutes before"
        case fifteen    = "15 minutes before"
        case thirty     = "30 minutes before"
        case oneHour    = "1 hour before"
        case oneDay     = "1 day before"
    }

    init(store: NativeCalendarService, preselectedDate: Date, onSave: @escaping (EKEvent, CalendarEvent.EventCategory, CalendarEvent.RecurrenceRule, String, String, String, String, [UUID], CalendarEvent.EventScope) -> Void) {
        self.store           = store
        self.preselectedDate = preselectedDate
        self.onSave          = onSave
        let cal   = Calendar.current
        let hour  = cal.component(.hour, from: preselectedDate)
        let start = cal.date(bySettingHour: hour + 1, minute: 0, second: 0, of: preselectedDate) ?? preselectedDate
        let end   = cal.date(byAdding: .hour, value: 1, to: start) ?? start
        _startDate = State(initialValue: start)
        _endDate   = State(initialValue: end)
    }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {

                // MARK: Title + Location
                Section {
                    TextField("Title", text: $title)
                        .font(.system(size: 17))
                        .focused($titleFocused)
                        .submitLabel(.next)
                        .onSubmit { locationFocused = true }
                    TextField("Location", text: $location)
                        .font(.system(size: 17))
                        .focused($locationFocused)
                        .submitLabel(.next)
                        .onSubmit { notesFocused = true }
                }

                // MARK: Scope — required; appears directly under title
                Section {
                    Picker("Event Type", selection: $eventScope) {
                        ForEach(CalendarEvent.EventScope.allCases, id: \.self) { s in
                            Label(s.rawValue, systemImage: s.iconName).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }

                // MARK: Time
                Section {
                    // All-day toggle
                    Toggle("All-day", isOn: $isAllDay.animation())
                        .onChange(of: isAllDay) { _, allDay in
                            if allDay {
                                showStartDatePicker = false
                                showStartTimePicker = false
                                showEndDatePicker   = false
                                showEndTimePicker   = false
                            }
                        }

                    // Starts row
                    HStack {
                        Text("Starts")
                            .foregroundColor(.primary)
                        Spacer()
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showStartDatePicker.toggle()
                                    showStartTimePicker = false
                                    showEndDatePicker   = false
                                    showEndTimePicker   = false
                                }
                            } label: {
                                Text(startDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .font(.system(size: 15, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(showStartDatePicker ? Color.systemRed : Color(.systemGray5))
                                    .foregroundColor(showStartDatePicker ? .white : .primary)
                                    .cornerRadius(7)
                            }
                            .buttonStyle(.plain)
                            if !isAllDay {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showStartTimePicker.toggle()
                                        showStartDatePicker = false
                                        showEndDatePicker   = false
                                        showEndTimePicker   = false
                                    }
                                } label: {
                                    Text(startDate.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                                        .font(.system(size: 15, weight: .medium))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(showStartTimePicker ? Color.systemRed : Color(.systemGray5))
                                        .foregroundColor(showStartTimePicker ? .white : .primary)
                                        .cornerRadius(7)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if showStartDatePicker {
                        DatePicker(
                            "",
                            selection: $startDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: startDate) { _, newStart in
                            if endDate <= newStart {
                                endDate = Calendar.current.date(byAdding: .hour, value: 1, to: newStart) ?? newStart
                            }
                        }
                    }

                    if showStartTimePicker {
                        TimeWheelPicker(date: $startDate)
                            .onChange(of: startDate) { _, newStart in
                                if endDate <= newStart {
                                    endDate = Calendar.current.date(byAdding: .hour, value: 1, to: newStart) ?? newStart
                                }
                            }
                    }

                    // Ends row
                    HStack {
                        Text("Ends")
                            .foregroundColor(.primary)
                        Spacer()
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showEndDatePicker.toggle()
                                    showEndTimePicker   = false
                                    showStartDatePicker = false
                                    showStartTimePicker = false
                                }
                            } label: {
                                Text(endDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .font(.system(size: 15, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(showEndDatePicker ? Color.systemRed : Color(.systemGray5))
                                    .foregroundColor(showEndDatePicker ? .white : .primary)
                                    .cornerRadius(7)
                            }
                            .buttonStyle(.plain)
                            if !isAllDay {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showEndTimePicker.toggle()
                                        showEndDatePicker   = false
                                        showStartDatePicker = false
                                        showStartTimePicker = false
                                    }
                                } label: {
                                    Text(endDate.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                                        .font(.system(size: 15, weight: .medium))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(showEndTimePicker ? Color.systemRed : Color(.systemGray5))
                                        .foregroundColor(showEndTimePicker ? .white : .primary)
                                        .cornerRadius(7)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if showEndDatePicker {
                        DatePicker(
                            "",
                            selection: $endDate,
                            in: startDate...,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    }

                    if showEndTimePicker {
                        TimeWheelPicker(date: $endDate)
                            .onChange(of: endDate) { _, newEnd in
                                if newEnd < startDate {
                                    endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
                                }
                            }
                    }

                    // Travel Time
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTravelPicker.toggle()
                                showRepeatPicker = false
                                showAlertPicker  = false
                            }
                        } label: {
                            HStack {
                                Text("Travel Time").foregroundColor(.primary)
                                Spacer()
                                Text(travelTime.rawValue).foregroundColor(.secondary)
                                Image(systemName: showTravelPicker ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showTravelPicker {
                            Picker("Travel Time", selection: $travelTime) {
                                ForEach(TravelOption.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 150)
                        }
                    }
                }

                // MARK: Repeat
                Section {
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRepeatPicker.toggle()
                                showTravelPicker = false
                                showAlertPicker  = false
                            }
                        } label: {
                            HStack {
                                Text("Repeat").foregroundColor(.primary)
                                Spacer()
                                Text(repeatRule.rawValue).foregroundColor(.secondary)
                                Image(systemName: showRepeatPicker ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showRepeatPicker {
                            Picker("Repeat", selection: $repeatRule) {
                                ForEach(RepeatOption.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 150)
                        }
                    }
                }

                // MARK: Invitees
                let members = HouseholdService.shared.household?.members ?? []
                if !members.isEmpty {
                    Section("Invitees") {
                        ForEach(members) { member in
                            let memberUUID = UUID(uuidString: member.id)
                            Button {
                                guard let uuid = memberUUID else { return }
                                if inviteeIDs.contains(uuid) {
                                    inviteeIDs.remove(uuid)
                                } else {
                                    inviteeIDs.insert(uuid)
                                }
                            } label: {
                                HStack {
                                    Text(member.username)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if let uuid = memberUUID, inviteeIDs.contains(uuid) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.systemRed)
                                    }
                                }
                            }
                        }
                    }
                }

                // MARK: Category
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(CalendarEvent.EventCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                        }
                    }
                    .onChange(of: category) { _, newCat in
                        selectedColorHex = newCat.defaultColorHex
                    }
                }

                // MARK: Alert
                Section {
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAlertPicker.toggle()
                                showTravelPicker = false
                                showRepeatPicker = false
                            }
                        } label: {
                            HStack {
                                Text("Alert").foregroundColor(.primary)
                                Spacer()
                                Text(alertOption.rawValue).foregroundColor(.secondary)
                                Image(systemName: showAlertPicker ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showAlertPicker {
                            Picker("Alert", selection: $alertOption) {
                                ForEach(AlertOption.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 150)
                        }
                    }
                }

                // MARK: Color
                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(eventColorPalette, id: \.self) { hex in
                                Button {
                                    selectedColorHex = hex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex) ?? .gray)
                                            .frame(width: 30, height: 30)
                                        if selectedColorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColorHex == hex ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 2.5)
                                            .padding(-3)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: Notes
                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 16))
                        .focused($notesFocused)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("New Event")
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    titleFocused = true
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.systemRed)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEvent() }
                        .foregroundColor(canSave ? Color.primary : Color(.systemGray4))
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Save
    private func saveEvent() {
        let eventTitle = title.trimmingCharacters(in: .whitespaces)

        let recurrence: CalendarEvent.RecurrenceRule
        switch repeatRule {
        case .never:    recurrence = .never
        case .daily:    recurrence = .daily
        case .weekly:   recurrence = .weekly
        case .biweekly: recurrence = .biweekly
        case .monthly:  recurrence = .monthly
        case .yearly:   recurrence = .yearly
        }

        // Build a minimal EKEvent shell so the onSave signature is satisfied.
        // Hemvo persists its own CalendarEvent in UserDefaults; we don't
        // write this to the native EKEventStore.
        let ekStore    = EKEventStore()
        let ekEvent    = EKEvent(eventStore: ekStore)
        ekEvent.title    = eventTitle
        ekEvent.location = location.isEmpty ? nil : location
        ekEvent.notes    = notes.isEmpty ? nil : notes
        ekEvent.isAllDay = isAllDay
        ekEvent.startDate = startDate
        ekEvent.endDate   = endDate

        onSave(ekEvent, category, recurrence, travelTime.rawValue, alertOption.rawValue, selectedColorHex, location, Array(inviteeIDs), eventScope)
        dismiss()
    }

}

// MARK: - Color extension for system red
private extension Color {
    static var systemRed: Color { Color(UIColor.systemRed) }
}

// MARK: - Edit Calendar Event Sheet
struct EditCalendarEventSheet: View {
    let event: CalendarEvent
    @ObservedObject var vm: ScheduleViewModel
    @Environment(\.dismiss) var dismiss

    private enum Field { case title, location, notes }
    @FocusState private var focus: Field?

    @State private var title      = ""
    @State private var location   = ""
    @State private var notes      = ""
    @State private var isAllDay   = false
    @State private var startDate  = Date()
    @State private var endDate    = Date()
    @State private var category   = CalendarEvent.EventCategory.general
    @State private var assignedTo:       UUID? = nil
    @State private var inviteeIDs:       Set<UUID> = []
    @State private var repeatRule        = CalendarEvent.RecurrenceRule.never
    @State private var travelTime        = EditTravelOption.none
    @State private var alertOption       = EditAlertOption.none
    @State private var selectedColorHex  = ""
    @State private var eventScope        = CalendarEvent.EventScope.personal
    @State private var showStartDate = false
    @State private var showStartTime = false
    @State private var showEndDate   = false
    @State private var showEndTime   = false
    @State private var showRepeat    = false
    @State private var showTravel    = false
    @State private var showAlert     = false
    @State private var hasLoaded     = false

    enum EditTravelOption: String, CaseIterable {
        case none    = "None"
        case five    = "5 minutes"
        case fifteen = "15 minutes"
        case thirty  = "30 minutes"
        case hour    = "1 hour"
        case ninety  = "1.5 hours"
        case two     = "2 hours"
    }

    enum EditAlertOption: String, CaseIterable {
        case none    = "None"
        case atTime  = "At time of event"
        case five    = "5 minutes before"
        case fifteen = "15 minutes before"
        case thirty  = "30 minutes before"
        case oneHour = "1 hour before"
        case oneDay  = "1 day before"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Title", text: $title)
                        .font(.system(size: 17))
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focus = .location }
                    TextField("Location", text: $location)
                        .font(.system(size: 17))
                        .focused($focus, equals: .location)
                        .submitLabel(.next)
                        .onSubmit { focus = .notes }
                }

                Section {
                    Picker("Event Type", selection: $eventScope) {
                        ForEach(CalendarEvent.EventScope.allCases, id: \.self) { s in
                            Label(s.rawValue, systemImage: s.iconName).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("All-day", isOn: $isAllDay.animation())
                        .onChange(of: isAllDay) { _, allDay in
                            if allDay {
                                showStartDate = false
                                showStartTime = false
                                showEndDate   = false
                                showEndTime   = false
                            }
                        }

                    // Starts
                    HStack {
                        Text("Starts")
                        Spacer()
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showStartDate.toggle()
                                    showStartTime = false
                                    showEndDate   = false
                                    showEndTime   = false
                                }
                            } label: {
                                Text(startDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(showStartDate ? Color(UIColor.systemRed) : Color(.systemGray5))
                                    .foregroundColor(showStartDate ? .white : .primary)
                                    .cornerRadius(7)
                            }
                            .buttonStyle(.plain)
                            if !isAllDay {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showStartTime.toggle()
                                        showStartDate = false
                                        showEndDate   = false
                                        showEndTime   = false
                                    }
                                } label: {
                                    Text(startDate.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(showStartTime ? Color(UIColor.systemRed) : Color(.systemGray5))
                                        .foregroundColor(showStartTime ? .white : .primary)
                                        .cornerRadius(7)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if showStartDate {
                        DatePicker("", selection: $startDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical).labelsHidden()
                            .onChange(of: startDate) { _, s in
                                if endDate <= s {
                                    endDate = Calendar.current.date(byAdding: .hour, value: 1, to: s) ?? s
                                }
                            }
                    }
                    if showStartTime {
                        TimeWheelPicker(date: $startDate)
                            .onChange(of: startDate) { _, s in
                                if endDate <= s {
                                    endDate = Calendar.current.date(byAdding: .hour, value: 1, to: s) ?? s
                                }
                            }
                    }

                    // Ends
                    HStack {
                        Text("Ends")
                        Spacer()
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showEndDate.toggle()
                                    showEndTime   = false
                                    showStartDate = false
                                    showStartTime = false
                                }
                            } label: {
                                Text(endDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(showEndDate ? Color(UIColor.systemRed) : Color(.systemGray5))
                                    .foregroundColor(showEndDate ? .white : .primary)
                                    .cornerRadius(7)
                            }
                            .buttonStyle(.plain)
                            if !isAllDay {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showEndTime.toggle()
                                        showEndDate   = false
                                        showStartDate = false
                                        showStartTime = false
                                    }
                                } label: {
                                    Text(endDate.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(showEndTime ? Color(UIColor.systemRed) : Color(.systemGray5))
                                        .foregroundColor(showEndTime ? .white : .primary)
                                        .cornerRadius(7)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if showEndDate {
                        DatePicker("", selection: $endDate, in: startDate..., displayedComponents: [.date])
                            .datePickerStyle(.graphical).labelsHidden()
                    }
                    if showEndTime {
                        TimeWheelPicker(date: $endDate)
                            .onChange(of: endDate) { _, newEnd in
                                if newEnd < startDate {
                                    endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
                                }
                            }
                    }

                    // Travel Time
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTravel.toggle()
                                showRepeat = false
                                showAlert  = false
                            }
                        } label: {
                            HStack {
                                Text("Travel Time").foregroundColor(.primary)
                                Spacer()
                                Text(travelTime.rawValue).foregroundColor(.secondary)
                                Image(systemName: showTravel ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showTravel {
                            Picker("Travel Time", selection: $travelTime) {
                                ForEach(EditTravelOption.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 150)
                        }
                    }
                }

                // MARK: Repeat
                Section {
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRepeat.toggle()
                                showTravel = false
                                showAlert  = false
                            }
                        } label: {
                            HStack {
                                Text("Repeat").foregroundColor(.primary)
                                Spacer()
                                Text(repeatRule.rawValue).foregroundColor(.secondary)
                                Image(systemName: showRepeat ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showRepeat {
                            Picker("Repeat", selection: $repeatRule) {
                                ForEach(CalendarEvent.RecurrenceRule.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 150)
                        }
                    }
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(CalendarEvent.EventCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                        }
                    }
                    .onChange(of: category) { _, newCat in
                        guard hasLoaded else { return }
                        selectedColorHex = newCat.defaultColorHex
                    }
                }

                // MARK: Alert
                Section {
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAlert.toggle()
                                showTravel = false
                                showRepeat = false
                            }
                        } label: {
                            HStack {
                                Text("Alert").foregroundColor(.primary)
                                Spacer()
                                Text(alertOption.rawValue).foregroundColor(.secondary)
                                Image(systemName: showAlert ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showAlert {
                            Picker("Alert", selection: $alertOption) {
                                ForEach(EditAlertOption.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 150)
                        }
                    }
                }

                // MARK: Color
                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(eventColorPalette, id: \.self) { hex in
                                Button {
                                    selectedColorHex = hex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex) ?? .gray)
                                            .frame(width: 30, height: 30)
                                        if selectedColorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColorHex == hex ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 2.5)
                                            .padding(-3)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: Invitees
                let editMembers = HouseholdService.shared.household?.members ?? []
                if !editMembers.isEmpty {
                    Section("Invitees") {
                        ForEach(editMembers) { member in
                            let memberUUID = UUID(uuidString: member.id)
                            Button {
                                guard let uuid = memberUUID else { return }
                                if inviteeIDs.contains(uuid) {
                                    inviteeIDs.remove(uuid)
                                } else {
                                    inviteeIDs.insert(uuid)
                                }
                            } label: {
                                HStack {
                                    Text(member.username)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if let uuid = memberUUID, inviteeIDs.contains(uuid) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color(UIColor.systemRed))
                                    }
                                }
                            }
                        }
                    }
                }

                // MARK: Assign To
                if !vm.householdMembers.isEmpty {
                    Section("Assign To") {
                        Picker("Member", selection: $assignedTo) {
                            Text("No one").tag(nil as UUID?)
                            ForEach(vm.householdMembers) { m in
                                Text(m.name).tag(m.id as UUID?)
                            }
                        }
                    }
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 16))
                        .focused($focus, equals: .notes)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundColor(Color(UIColor.systemRed))
                }
            }
            .onAppear {
                title            = event.title
                location         = event.location
                notes            = event.notes
                isAllDay         = event.isAllDay
                startDate        = event.date
                endDate          = event.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: event.date) ?? event.date
                category         = event.category
                assignedTo       = event.assignedToID
                inviteeIDs       = Set(event.inviteeIDs)
                repeatRule       = event.repeatRule
                travelTime       = EditTravelOption(rawValue: event.travelTime) ?? .none
                alertOption      = EditAlertOption(rawValue: event.alertOption) ?? .none
                selectedColorHex = event.colorHex
                eventScope       = event.scope
                // Delay so the onChange(of: category) triggered above fires first (with
                // hasLoaded = false, so it is skipped), before we allow user changes.
                DispatchQueue.main.async { hasLoaded = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focus = .title
                }
            }
        }
    }

    private func save() {
        var updated           = event
        updated.title         = title.trimmingCharacters(in: .whitespaces)
        updated.location      = location
        updated.notes         = notes
        updated.isAllDay      = isAllDay
        updated.date          = startDate
        updated.endDate       = endDate
        updated.category      = category
        updated.colorHex      = selectedColorHex
        updated.assignedToID  = assignedTo
        updated.inviteeIDs    = Array(inviteeIDs)
        updated.repeatRule    = repeatRule
        updated.travelTime    = travelTime.rawValue
        updated.alertOption   = alertOption.rawValue
        updated.scope         = eventScope
        vm.updateEvent(updated)
        dismiss()
    }
}

// MARK: - Event Detail Sheet
struct EventDetailSheet: View {
    let event:          CalendarEvent
    var assignedMember: HouseholdMember? = nil
    let onEdit:         () -> Void
    let onDelete:       () -> Void
    var canDelete:      Bool = true
    var canEdit:        Bool = true

    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL

    private var color: Color { Color(hex: event.colorHex) ?? Color(UIColor.systemRed) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Colored header ───────────────────────────
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [color.opacity(0.85), color],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .frame(minHeight: 90)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: event.category.iconName)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                                Text(event.category.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .heavy)).kerning(1.2)
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: event.scope.iconName)
                                        .font(.system(size: 9, weight: .bold))
                                    Text(event.scope.rawValue.uppercased())
                                        .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                            }
                            Text(event.title)
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }
                        .padding(20)
                    }

                    // ── Info rows ────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {

                        // Date
                        infoRow(icon: "calendar", iconColor: color) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                                    .font(.system(size: 15, weight: .semibold))
                                if event.isAllDay {
                                    Text("All Day")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        divRow

                        // Time (if not all-day)
                        if !event.isAllDay {
                            infoRow(icon: "clock.fill", iconColor: color) {
                                HStack(spacing: 8) {
                                    Text(event.date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                                        .font(.system(size: 15, weight: .semibold))
                                    if let end = event.endDate {
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Text(end.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                                            .font(.system(size: 15, weight: .semibold))
                                        let mins = Int(end.timeIntervalSince(event.date) / 60)
                                        Text("(\(mins) min)")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            divRow
                        }

                        // Location (if set) — tap opens Apple Maps, long-press for other apps
                        if !event.location.isEmpty {
                            divRow
                            infoRow(icon: "mappin.and.ellipse", iconColor: color) {
                                Menu {
                                    Button { openLocation(in: .appleMaps) } label: {
                                        Label("Open in Apple Maps", systemImage: "map.fill")
                                    }
                                    Button { openLocation(in: .googleMaps) } label: {
                                        Label("Open in Google Maps", systemImage: "map")
                                    }
                                    Button { openLocation(in: .waze) } label: {
                                        Label("Open in Waze", systemImage: "car.fill")
                                    }
                                    Button { UIPasteboard.general.string = event.location } label: {
                                        Label("Copy Location", systemImage: "doc.on.doc")
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(event.location)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(color)
                                            .multilineTextAlignment(.leading)
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                } primaryAction: {
                                    openLocation(in: .appleMaps)
                                }
                            }
                        }

                        // Category
                        infoRow(icon: event.category.iconName, iconColor: color) {
                            HStack(spacing: 8) {
                                Text(event.category.rawValue)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(color)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(color.opacity(0.1))
                                    .cornerRadius(20)
                            }
                        }

                        // Scope
                        divRow
                        infoRow(icon: event.scope.iconName, iconColor: color) {
                            Text(event.scope.rawValue)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(color)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(color.opacity(0.1))
                                .cornerRadius(20)
                        }

                        // Repeat
                        divRow
                        infoRow(icon: "repeat", iconColor: color) {
                            Text(event.repeatRule.rawValue)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                        }

                        // Travel Time
                        divRow
                        infoRow(icon: "car.fill", iconColor: color) {
                            Text(event.travelTime)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                        }

                        // Alert
                        divRow
                        infoRow(icon: "bell.fill", iconColor: color) {
                            Text(event.alertOption)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                        }

                        // Invitees
                        if !event.inviteeIDs.isEmpty {
                            let members = HouseholdService.shared.household?.members ?? []
                            let names: [String] = event.inviteeIDs.compactMap { id in
                                members.first { $0.id == id.uuidString }?.username
                            }
                            if !names.isEmpty {
                                divRow
                                infoRow(icon: "person.2.fill", iconColor: color) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("INVITEES")
                                            .font(.system(size: 9, weight: .heavy)).kerning(1.2)
                                            .foregroundColor(.secondary)
                                        FlowLayout(spacing: 6) {
                                            ForEach(names, id: \.self) { name in
                                                Text("@\(name)")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(color)
                                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                                    .background(color.opacity(0.1))
                                                    .cornerRadius(20)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Notes
                        divRow
                        infoRow(icon: "note.text", iconColor: color) {
                            Text(event.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? "No notes" : event.notes)
                                .font(.system(size: 15))
                                .foregroundColor(event.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                 ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        divRow

                        // Created / ID
//                        infoRow(icon: "info.circle.fill", iconColor: Color(.systemGray3)) {
//                            VStack(alignment: .leading, spacing: 2) {
//                                Text("Hemvo Event")
//                                    .font(.system(size: 13, weight: .medium))
//                                    .foregroundColor(.secondary)
//                                Text("ID: \(event.id.uuidString.prefix(8))…")
//                                    .font(.system(size: 11))
//                                    .foregroundColor(Color(.systemGray3))
//                            }
//                        }
                    }
                    .background(Color(.systemBackground))

                    // ── Action buttons ────────────────────────────
                    HStack(spacing: 12) {
                        // Edit — hidden for Teen role
                        if canEdit {
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onEdit() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "pencil").font(.system(size: 14, weight: .semibold))
                                    Text("Edit").font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(color)
                                .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                        }

                        // Delete — only for the creator
                        if canDelete {
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDelete() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                                    Text("Delete").font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(color)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var divRow: some View {
        Divider().padding(.leading, 60)
    }

    private enum MapApp {
        case appleMaps, googleMaps, waze
    }

    // Universal links: open the app when installed, otherwise fall back to the browser
    private func openLocation(in app: MapApp) {
        var components: URLComponents?
        switch app {
        case .appleMaps:
            components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [URLQueryItem(name: "q", value: event.location)]
        case .googleMaps:
            components = URLComponents(string: "https://www.google.com/maps/search/")
            components?.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "query", value: event.location)
            ]
        case .waze:
            components = URLComponents(string: "https://waze.com/ul")
            components?.queryItems = [URLQueryItem(name: "q", value: event.location)]
        }
        guard let url = components?.url else { return }
        openURL(url)
    }

    @ViewBuilder
    private func infoRow<C: View>(icon: String, iconColor: Color, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .padding(.leading, 20)

            content()
                .padding(.vertical, 10)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Compatibility stubs
struct CalendarStrip: View {
    @Binding var selectedDate: Date
    @ObservedObject var vm: ScheduleViewModel

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
                    let hasEvent   = !vm.events(on: day).isEmpty
                    Button { selectedDate = day } label: {
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isSelected ? (Color(hex: "#C8922A") ?? .clear) : .secondary)
                            ZStack {
                                Circle()
                                    .fill(isSelected
                                          ? (Color(hex: "#C8922A") ?? .clear)
                                          : (isToday ? (Color(hex: "#C8922A")?.opacity(0.15) ?? .clear) : Color.clear))
                                    .frame(width: 34, height: 34)
                                Text(day.formatted(.dateTime.day()))
                                    .font(.system(size: 15, weight: isToday || isSelected ? .bold : .regular))
                                    .foregroundColor(isSelected ? .white : (isToday ? (Color(hex: "#C8922A") ?? .clear) : .primary))
                            }
                            Circle()
                                .fill(hasEvent ? (Color(hex: "#E53935") ?? .clear) : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

struct EventDetailRow: View {
    let event: CalendarEvent
    let member: HouseholdMember?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: event.colorHex) ?? .clear)
                .frame(width: 4)
                .padding(.vertical, 4)
                .padding(.leading, 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(event.formattedTime)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Image(systemName: event.category.iconName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let m = member {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill").font(.system(size: 8))
                            Text(m.name).font(.system(size: 10, weight: .medium))
                        }.foregroundColor(.secondary)
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

struct TaskDetailRow: View {
    let task: HouseTask; let member: HouseholdMember?
    let onToggle: () -> Void; let onDelete: () -> Void
    var body: some View {
        CalendarTaskRow(task: task, member: member, onToggle: onToggle, onDelete: onDelete)
    }
}

// MARK: - CalendarTaskRow (used by DashboardView)
struct CalendarTaskRow: View {
    let task: HouseTask; let member: HouseholdMember?
    let onToggle: () -> Void; let onDelete: () -> Void

    var priorityColor: Color {
        switch task.priority {
        case .high:   return Color(hex: "#C0392B") ?? .clear
        case .medium: return Color(hex: "#E67E22") ?? .clear
        case .low:    return Color(hex: "#3D7A52") ?? .clear
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { onToggle() } label: {
                ZStack {
                    Circle().stroke(task.isComplete ? Color(hex: "#3D7A52") ?? .clear : Color(.systemGray4), lineWidth: 2)
                        .frame(width: 26, height: 26)
                    if task.isComplete {
                        Circle().fill(Color(hex: "#3D7A52") ?? .clear).frame(width: 26, height: 26)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundColor(.white)
                    }
                }
                .animation(.spring(response: 0.25), value: task.isComplete)
            }
            .buttonStyle(.plain).padding(.leading, 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 14, weight: .bold))
                    .strikethrough(task.isComplete)
                    .foregroundColor(task.isComplete ? .secondary : .primary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(task.priority.label)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(priorityColor)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(priorityColor.opacity(0.1)).cornerRadius(20)
                    if let m = member {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill").font(.system(size: 8))
                            Text(m.name).font(.system(size: 10, weight: .medium))
                        }.foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button { onDelete() } label: {
                Image(systemName: "trash").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red.opacity(0.6))
                    .frame(width: 28, height: 28).background(Color.red.opacity(0.07)).clipShape(Circle())
            }
            .buttonStyle(.plain).padding(.trailing, 14)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - FlowLayout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let placements = arrange(width: proposal.width ?? 0, subviews: subviews)
        return placements.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placements = arrange(width: bounds.width, subviews: subviews)
        for (point, subview) in zip(placements.points, subviews) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                          proposal: .unspecified)
        }
    }

    private struct Arranged { var size: CGSize; var points: [CGPoint] }

    private func arrange(width: CGFloat, subviews: Subviews) -> Arranged {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for subview in subviews {
            let sz = subview.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            points.append(CGPoint(x: x, y: y))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return Arranged(size: CGSize(width: width, height: y + rowH), points: points)
    }
}

#Preview { FamilyCalendarView() }
