//
//  SyncContextCoordinator.swift
//  closet
//

import CoreData
import Foundation

/// Owns the sync background context and merges saves into the view context.
final class SyncContextCoordinator: @unchecked Sendable {
    private(set) var viewContext: NSManagedObjectContext?
    private(set) var syncContext: NSManagedObjectContext?
    private var saveObserver: NSObjectProtocol?

    func configure(container: NSPersistentContainer) {
        viewContext = container.viewContext

        let background = container.newBackgroundContext()
        background.name = "SyncServiceBackground"
        background.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        syncContext = background

        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }

        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: background,
            queue: nil
        ) { [weak container] notification in
            guard let viewContext = container?.viewContext else { return }
            viewContext.perform {
                viewContext.mergeChanges(fromContextDidSave: notification)
            }
        }
    }

    func performOnSyncContext<T>(
        _ work: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        guard let syncContext else {
            throw SyncError.noContext
        }
        return try await withCheckedThrowingContinuation { continuation in
            syncContext.perform {
                do {
                    continuation.resume(returning: try work(syncContext))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func saveSyncContext() async throws {
        try await performOnSyncContext { context in
            guard context.hasChanges else { return }
            try context.save()
        }
    }

    func saveViewContextIfNeeded() throws {
        guard let viewContext else { return }
        if viewContext.hasChanges {
            try viewContext.save()
        }
    }
}
