// PersistenceService.swift
// Hemvo
// CoreData stack. All household data lives in Supabase; CoreData handles
// local entity cleanup on account deletion and is available for future
// device-only features. CloudKit sync is intentionally not wired up —
// Supabase is the single source of truth for multi-user household data.

internal import CoreData
internal import Foundation

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

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                fatalError("CoreData failed to load: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
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
}
