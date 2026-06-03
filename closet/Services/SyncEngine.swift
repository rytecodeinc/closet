//
//  SyncEngine.swift
//  closet
//

import CoreData
import Foundation

typealias SyncProgressHandler = @Sendable (_ status: String, _ progress: Double) -> Void

/// Background actor isolating sync Core Data work from the main thread.
actor SyncEngine {
    static let shared = SyncEngine()

    private let coordinator = SyncContextCoordinator()
    private var onPurgeTombstones: (@Sendable () -> Void)?

    private init() {}

    func configure(
        container: NSPersistentContainer,
        onPurgeTombstones: (@Sendable () -> Void)?
    ) {
        coordinator.configure(container: container)
        self.onPurgeTombstones = onPurgeTombstones
    }

    var viewContext: NSManagedObjectContext? {
        coordinator.viewContext
    }

    func saveViewContextIfNeeded() async throws {
        try await MainActor.run {
            try coordinator.saveViewContextIfNeeded()
        }
    }

    func performOnSyncContext<T>(
        _ work: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await coordinator.performOnSyncContext(work)
    }

    func saveSyncContext() async throws {
        try await coordinator.saveSyncContext()
    }

    func schedulePurgeCallback() {
        onPurgeTombstones?()
    }

    /// MainActor-isolated Supabase access for network calls from the sync actor.
    func getSupabase() async -> SupabaseService {
        await MainActor.run { SupabaseService.shared }
    }

    func withSyncItem<T>(
        _ objectID: NSManagedObjectID,
        _ work: @escaping (Item) throws -> T
    ) async throws -> T {
        try await performOnSyncContext { ctx in
            guard let item = try ctx.existingObject(with: objectID) as? Item else {
                throw SyncError.noContext
            }
            return try work(item)
        }
    }
}
