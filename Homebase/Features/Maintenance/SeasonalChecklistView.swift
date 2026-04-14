//  SeasonalChecklistView.swift
//  HomeBase
//  Four-season home maintenance checklist with progress tracking.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

struct SeasonalChecklistView: View {

    @Environment(\.dismiss) var dismiss
    @State private var currentSeason: Season         = Season.current
    @State private var completedIDs: Set<UUID>       = []
    @State private var showResetAlert: Bool          = false

    private let storageKey = "hb_seasonalCompleted"

    var tasks: [SeasonalTask] { currentSeason.tasks }

    var completedCount: Int { tasks.filter { completedIDs.contains($0.id) }.count }
    var progress: Double    { guard !tasks.isEmpty else { return 0 }
                              return Double(completedCount) / Double(tasks.count) }
    var allDone: Bool       { completedCount == tasks.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.homeBaseBackground.ignoresSafeArea()
                VStack(spacing: 0) {

                    // Season picker tabs
                    seasonPicker
                        .background(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                    ScrollView {
                        VStack(spacing: 16) {

                            // Progress card
                            progressCard
                                .padding(.horizontal)
                                .padding(.top, 16)

                            // All done banner
                            if allDone {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.homeBaseGreen)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("All Done! 🎉")
                                            .font(.headline)
                                        Text("Your \(currentSeason.rawValue) checklist is complete.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color.homeBaseGreen.opacity(0.1))
                                .cornerRadius(14)
                                .padding(.horizontal)
                            }

                            // Task list
                            VStack(spacing: 10) {
                                ForEach(tasks) { task in
                                    SeasonalTaskRow(
                                        task: task,
                                        isComplete: completedIDs.contains(task.id)
                                    ) {
                                        toggleTask(task)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationTitle("\(currentSeason.emoji) \(currentSeason.rawValue) Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showResetAlert = true } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.secondary)
                    }
                    .disabled(completedIDs.isEmpty)
                }
            }
            .alert("Reset Checklist", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) {
                    withAnimation { completedIDs.removeAll() }
                    persist()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Clear all completed items for \(currentSeason.rawValue)?")
            }
            .onAppear { loadCompleted() }
        }
    }

    // MARK: - Season Picker
    private var seasonPicker: some View {
        HStack(spacing: 0) {
            ForEach(Season.allCases) { season in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentSeason = season
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(season.emoji).font(.title2)
                        Text(season.rawValue)
                            .font(.caption).bold()
                            .foregroundColor(currentSeason == season ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(currentSeason == season ? Color.homeBaseGreen : Color.clear)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentSeason)
    }

    // MARK: - Progress Card
    private var progressCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(completedCount) of \(tasks.count) complete")
                        .font(.headline)
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.homeBaseGreen, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5), value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.caption).bold()
                        .foregroundColor(.homeBaseGreen)
                }
                .frame(width: 56, height: 56)
            }
            ProgressView(value: progress)
                .tint(.homeBaseGreen)
        }
        .padding()
        .cardStyle()
    }

    private var progressLabel: String {
        if allDone            { return "All tasks complete — great work!" }
        if completedCount == 0 { return "Tap tasks below to mark complete" }
        return "\(tasks.count - completedCount) tasks remaining"
    }

    // MARK: - Toggle Task
    private func toggleTask(_ task: SeasonalTask) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if completedIDs.contains(task.id) {
                completedIDs.remove(task.id)
            } else {
                completedIDs.insert(task.id)
            }
        }
        persist()
    }

    // MARK: - Persistence
    private func persist() {
        let ids = completedIDs.map { $0.uuidString }
        UserDefaults.standard.set(ids, forKey: storageKey)
    }

    private func loadCompleted() {
        let ids = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        completedIDs = Set(ids.compactMap { UUID(uuidString: $0) })
    }
}

// MARK: - SeasonalTaskRow
struct SeasonalTaskRow: View {
    let task: SeasonalTask
    let isComplete: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button { onToggle() } label: {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isComplete ? .homeBaseGreen : Color(.systemGray3))
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline).bold()
                    .strikethrough(isComplete)
                    .foregroundColor(isComplete ? .secondary : .primary)
                Text(task.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.caption).bold()
                    .foregroundColor(.homeBaseGreen)
            }
        }
        .padding()
        .cardStyle()
        .animation(.easeInOut(duration: 0.15), value: isComplete)
    }
}

#Preview {
    SeasonalChecklistView()
}
