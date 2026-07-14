// PersistenceService.swift
// Hemvo
// CoreData stack. All household data lives in Supabase; CoreData handles
// local entity cleanup on account deletion and is available for future
// device-only features. CloudKit sync is intentionally not wired up —
// Supabase is the single source of truth for multi-user household data.

internal import CoreData
internal import Foundation
internal import OSLog

final class PersistenceService {

    static let shared   = PersistenceService()
    static let preview  = PersistenceService(inMemory: true)

    let container: NSPersistentContainer

    // MARK: - Init

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Hemvo")

        if inMemory {
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        }

        var loadError: NSError?
        container.loadPersistentStores { _, error in
            loadError = error as NSError?
        }

        // Every store on disk before this shipped was created against an empty model — the
        // model file was never compiled, so CoreData came up with no entities at all. Those
        // stores have to migrate to the real model, and a store that refuses to migrate must
        // not brick the app at launch. Nothing writes CoreData (Supabase is the source of
        // truth; this stack is a scaffold for offline caching), so the store holds nothing
        // worth rescuing: discard it and start clean rather than trapping.
        if let error = loadError {
            Logger.persistence.error("Store failed to load, recreating: \(error.localizedDescription)")
            destroyStore()

            var retryError: NSError?
            container.loadPersistentStores { _, error in
                retryError = error as NSError?
            }
            if let retryError {
                fatalError("CoreData failed to load after recreating the store: \(retryError), \(retryError.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Destroy Store

    /// Removes the store files so the next load starts from an empty store.
    private func destroyStore() {
        let coordinator = container.persistentStoreCoordinator
        for description in container.persistentStoreDescriptions {
            guard let url = description.url, url.isFileURL else { continue }
            do {
                try coordinator.destroyPersistentStore(at: url, type: .sqlite)
            } catch {
                Logger.persistence.error("Could not destroy store at \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Save

    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            Logger.persistence.error("Save failed: \(error.localizedDescription)")
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
                catch { Logger.persistence.error("Background save failed: \(error.localizedDescription)") }
            }
        }
    }
}
