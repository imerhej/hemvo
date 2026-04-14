//  PersistenceService.swift
//  HomeBase
//  CoreData + CloudKit stack. Provides NSManagedObjectContext to the app.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications


// MARK: - PersistenceService
final class PersistenceService {

    static let shared   = PersistenceService()
    static let preview  = PersistenceService(inMemory: true)

    let container: NSPersistentCloudKitContainer

    // MARK: - Init
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "HomeBase")

        if inMemory {
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        } else {
            configureCloudKit()
        }

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                // In production, handle this gracefully instead of crashing.
                fatalError("CoreData failed to load: \(error), \(error.userInfo)")
            }
            print("PersistenceService: Store loaded — \(description.url?.lastPathComponent ?? "unknown")")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Listen for remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remoteStoreChanged),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    // MARK: - CloudKit Config
    private func configureCloudKit() {
        guard let description = container.persistentStoreDescriptions.first else {
            print("PersistenceService: No persistent store description found.")
            return
        }
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey
        )
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        // Only attach CloudKit container if entitlement is configured
        #if !DEBUG
        description.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.homebase.app"
            )
        #endif
    }

    // MARK: - Save
    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            print("PersistenceService: Save failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Background Save
    func saveInBackground(_ block: @escaping (NSManagedObjectContext) -> Void) {
        let bgCtx = container.newBackgroundContext()
        bgCtx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        bgCtx.perform {
            block(bgCtx)
            if bgCtx.hasChanges {
                do { try bgCtx.save() }
                catch { print("PersistenceService: Background save failed — \(error)") }
            }
        }
    }

    // MARK: - Remote Change Handler
    @objc private func remoteStoreChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.container.viewContext.mergeChanges(fromContextDidSave: notification)
        }
    }
}
