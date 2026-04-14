//  MaintenanceViewModel.swift
//  HomeBase
//  Manages home maintenance items and seasonal checklists.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

@MainActor
final class MaintenanceViewModel: ObservableObject {

    @Published var items: [MaintenanceItem] = []

    // MARK: - Computed
    var overdueItems:  [MaintenanceItem] { items.filter { $0.isOverdue  }.sorted { $0.nextDue < $1.nextDue } }
    var dueSoonItems:  [MaintenanceItem] { items.filter { $0.isDueSoon  }.sorted { $0.nextDue < $1.nextDue } }
    var upToDateItems: [MaintenanceItem] { items.filter { $0.isUpToDate }.sorted { $0.nextDue < $1.nextDue } }

    func items(for area: MaintenanceItem.HomeArea) -> [MaintenanceItem] {
        items.filter { $0.area == area }
    }

    // MARK: - CRUD
    func addItem(_ item: MaintenanceItem) {
        items.append(item); persist()
    }

    func updateItem(_ item: MaintenanceItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) { items[idx] = item; persist() }
    }

    func markComplete(_ item: MaintenanceItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].markComplete(); persist()
        }
    }

    func deleteItem(_ item: MaintenanceItem) {
        items.removeAll { $0.id == item.id }; persist()
    }

    func deleteItems(at offsets: IndexSet, in source: [MaintenanceItem]) {
        offsets.forEach { deleteItem(source[$0]) }
    }

    // MARK: - Seed Default Chores (called on first launch)
    func seedDefaultsIfNeeded() {
        guard items.isEmpty else { return }
        let defaults: [(String, MaintenanceItem.HomeArea, MaintenanceItem.Frequency, Int)] = [
            ("Replace HVAC Filter",       .hvac,     .monthly,   30),
            ("Clean Gutters",             .yard,     .quarterly, 90),
            ("Test Smoke Detectors",      .general,  .monthly,   7),
            ("Deep Clean Refrigerator",   .kitchen,  .quarterly, 60),
            ("Inspect Fire Extinguisher", .general,  .annually,  365),
        ]
        let now = Date()
        for (title, area, freq, daysAhead) in defaults {
            let nextDue = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
            items.append(MaintenanceItem(title: title, area: area, frequency: freq, nextDue: nextDue))
        }
        persist()
    }

    // MARK: - Persistence
    private let storageKey = "hb_maintenanceItems"

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MaintenanceItem].self, from: data)
        else { return }
        items = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
