//  ScheduleViewModel.swift
//  HomeBase
//  Manages family calendar events and household tasks.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

@MainActor
final class ScheduleViewModel: ObservableObject {

    @Published var events:          [CalendarEvent]    = []
    @Published var tasks:           [HouseTask]        = []
    @Published var householdMembers: [HouseholdMember] = []

    // MARK: - Computed
    var upcomingEvents: [CalendarEvent] {
        events.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }
              .sorted { $0.date < $1.date }
    }

    var tasksDueToday: [HouseTask] {
        tasks.filter { $0.isDueToday && !$0.isComplete }
              .sorted { $0.priority.sortValue < $1.priority.sortValue }
    }

    var overdueTasks: [HouseTask] {
        tasks.filter { $0.isOverdue }
              .sorted { $0.dueDate < $1.dueDate }
    }

    func events(on date: Date) -> [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
              .sorted { $0.date < $1.date }
    }

    func tasks(on date: Date) -> [HouseTask] {
        tasks.filter { Calendar.current.isDate($0.dueDate, inSameDayAs: date) }
              .sorted { $0.priority.sortValue < $1.priority.sortValue }
    }

    func hasActivity(on date: Date) -> Bool {
        !events(on: date).isEmpty || !tasks(on: date).isEmpty
    }

    // MARK: - Member Lookup
    func member(for id: UUID?) -> HouseholdMember? {
        guard let id else { return nil }
        return householdMembers.first { $0.id == id }
    }

    // MARK: - Event CRUD
    func addEvent(_ event: CalendarEvent) {
        events.append(event); persist()
    }
    func updateEvent(_ event: CalendarEvent) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) { events[idx] = event; persist() }
    }
    func deleteEvent(_ event: CalendarEvent) {
        events.removeAll { $0.id == event.id }; persist()
    }

    // MARK: - Task CRUD
    func addTask(_ task: HouseTask) {
        tasks.append(task); persist()
    }
    func toggleTask(_ task: HouseTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].isComplete.toggle()
            tasks[idx].completedDate = tasks[idx].isComplete ? Date() : nil
            persist()
        }
    }
    func deleteTask(_ task: HouseTask) {
        tasks.removeAll { $0.id == task.id }; persist()
    }
    func deleteTasks(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets); persist()
    }

    // MARK: - Member CRUD
    func addMember(_ member: HouseholdMember) {
        householdMembers.append(member); persist()
    }
    func deleteMember(_ member: HouseholdMember) {
        householdMembers.removeAll { $0.id == member.id }; persist()
    }

    // MARK: - Persistence
    private let eventsKey  = "hb_events"
    private let tasksKey   = "hb_tasks"
    private let membersKey = "hb_members"

    init() { load() }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: eventsKey),
           let v = try? JSONDecoder().decode([CalendarEvent].self, from: d) { events = v }
        if let d = UserDefaults.standard.data(forKey: tasksKey),
           let v = try? JSONDecoder().decode([HouseTask].self, from: d) { tasks = v }
        if let d = UserDefaults.standard.data(forKey: membersKey),
           let v = try? JSONDecoder().decode([HouseholdMember].self, from: d) { householdMembers = v }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(events)          { UserDefaults.standard.set(d, forKey: eventsKey) }
        if let d = try? JSONEncoder().encode(tasks)           { UserDefaults.standard.set(d, forKey: tasksKey) }
        if let d = try? JSONEncoder().encode(householdMembers){ UserDefaults.standard.set(d, forKey: membersKey) }
    }
}
