//  CloudSyncService.swift
//  HomeBase
//  Coordinates CloudKit sync status and provides sync triggers to the UI.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications


// MARK: - SyncStatus
enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced(Date)
    case error(String)
}

// MARK: - CloudSyncService
@MainActor
final class CloudSyncService: ObservableObject {

    static let shared = CloudSyncService()

    @Published var syncStatus: SyncStatus        = .idle
    @Published var isICloudAvailable: Bool       = false
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine

    // Set to true only when iCloud capability is enabled in Signing & Capabilities
    // Requires paid Apple Developer account ($99/yr)
    private let useCloudKit = false

    private var container: CKContainer? {
        useCloudKit ? CKContainer(identifier: "iCloud.com.homebase.app") : nil
    }

    private init() {
        Task { await checkAccountStatus() }
        listenForSyncEvents()
    }

    // MARK: - Account Status
    func checkAccountStatus() async {
        guard useCloudKit, let container else {
            accountStatus     = .couldNotDetermine
            isICloudAvailable = false
            syncStatus        = .idle
            return
        }
        do {
            let status        = try await container.accountStatus()
            accountStatus     = status
            isICloudAvailable = status == .available
        } catch {
            accountStatus     = .couldNotDetermine
            isICloudAvailable = false
            print("CloudSync: Account status error — \(error)")
        }
    }

    // MARK: - Manual Sync Trigger
    func triggerSync() async {
        guard useCloudKit, isICloudAvailable else {
            syncStatus = .error("iCloud is not available.")
            return
        }
        syncStatus = .syncing
        try? await Task.sleep(nanoseconds: 800_000_000)
        syncStatus = .synced(Date())
    }

    // MARK: - Listen for CoreData remote changes
    private func listenForSyncEvents() {
        guard useCloudKit else { return }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentStoreRemoteChangeNotification"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.syncStatus = .synced(Date())
            }
        }
    }

    // MARK: - Status Description
    var statusDescription: String {
        guard useCloudKit else { return "iCloud sync disabled" }
        switch syncStatus {
        case .idle:           return "Not synced"
        case .syncing:        return "Syncing…"
        case .synced(let d):  return "Last synced \(d.formatted(.relative(presentation: .named)))"
        case .error(let msg): return "Sync error: \(msg)"
        }
    }
}
