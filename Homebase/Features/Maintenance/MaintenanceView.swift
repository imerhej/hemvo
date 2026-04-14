//  MaintenanceView.swift
//  HomeBase
//  Home maintenance tracker with area filters, status stats, and item cards.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications


struct MaintenanceView: View {

    @StateObject private var vm = MaintenanceViewModel()
    @State private var selectedArea: MaintenanceItem.HomeArea? = nil
    @State private var showAddChore    = false
    @State private var showSeasonal    = false
    @State private var showDeleteAlert = false
    @State private var itemToDelete: MaintenanceItem? = nil

    var filteredItems: [MaintenanceItem] {
        guard let area = selectedArea else { return vm.items }
        return vm.items(for: area)
    }

    var sortedItems: [MaintenanceItem] {
        filteredItems.sorted {
            if $0.isOverdue  != $1.isOverdue  { return $0.isOverdue }
            if $0.isDueSoon  != $1.isDueSoon  { return $0.isDueSoon }
            return $0.nextDue < $1.nextDue
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.homeBaseBackground.ignoresSafeArea()
                VStack(spacing: 0) {

                    // Stats bar
                    statsBar
                        .padding()
                        .background(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                    // Area filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            PillButton(title: "All", isSelected: selectedArea == nil) {
                                selectedArea = nil
                            }
                            ForEach(MaintenanceItem.HomeArea.allCases) { area in
                                PillButton(
                                    title: area.rawValue,
                                    isSelected: selectedArea == area
                                ) {
                                    selectedArea = selectedArea == area ? nil : area
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }

                    // Item list
                    if sortedItems.isEmpty {
                        EmptyStateView(
                            icon:        "wrench.and.screwdriver",
                            title:       "No Tasks Yet",
                            message:     "Add a chore or tap Seasonal Checklist to get started.",
                            buttonTitle: "Add Chore"
                        ) { showAddChore = true }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(sortedItems) { item in
                                    MaintenanceCard(
                                        item: item,
                                        onComplete: { vm.markComplete(item) },
                                        onDelete: {
                                            itemToDelete = item
                                            showDeleteAlert = true
                                        }
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Maintenance")
            .tint(.blue)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showAddChore = true } label: {
                            Label("Add Chore", systemImage: "plus.circle")
                        }
                        Button { showSeasonal = true } label: {
                            Label("Seasonal Checklist", systemImage: "leaf.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showAddChore)  { AddChoreView(vm: vm) }
            .sheet(isPresented: $showSeasonal)  { SeasonalChecklistView() }
            .alert("Delete Item", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete { vm.deleteItem(item) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Remove \"\(itemToDelete?.title ?? "this item")\" from your maintenance list?")
            }
            .onAppear { vm.seedDefaultsIfNeeded() }
        }
    }

    // MARK: - Stats Bar
    private var statsBar: some View {
        HStack(spacing: 0) {
            MaintenanceStatPill(
                value: "\(vm.overdueItems.count)",
                label: "Overdue",
                color: .red
            )
            Divider().frame(height: 32)
            MaintenanceStatPill(
                value: "\(vm.dueSoonItems.count)",
                label: "Due Soon",
                color: .orange
            )
            Divider().frame(height: 32)
            MaintenanceStatPill(
                value: "\(vm.upToDateItems.count)",
                label: "Up to Date",
                color: .homeBaseGreen
            )
        }
    }
}

// MARK: - MaintenanceCard
struct MaintenanceCard: View {
    let item: MaintenanceItem
    let onComplete: () -> Void
    let onDelete: () -> Void

    var statusColor: Color {
        item.isOverdue ? .red : item.isDueSoon ? .orange : .homeBaseGreen
    }

    var body: some View {
        HStack(spacing: 14) {
            // Area icon circle
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: item.area.iconName)
                    .foregroundColor(statusColor)
                    .font(.title3)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline).bold()
                HStack(spacing: 6) {
                    BadgeView(text: item.area.rawValue,      color: .blue,   style: .subtle)
                    BadgeView(text: item.frequency.rawValue, color: .purple, style: .subtle)
                }
                HStack(spacing: 4) {
                    Image(systemName: item.isOverdue ? "exclamationmark.circle.fill" : "clock")
                        .font(.caption2)
                    Text(item.statusLabel)
                        .font(.caption).bold()
                }
                .foregroundColor(statusColor)
            }

            Spacer()

            // Complete button
            Button { onComplete() } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.homeBaseGreen)
            }
        }
        .padding()
        .cardStyle()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { onComplete() } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .tint(.homeBaseGreen)
        }
    }
}

// MARK: - Stat Pill
struct MaintenanceStatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3).bold()
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MaintenanceView()
}
