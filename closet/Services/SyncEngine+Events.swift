//
//  SyncEngine+Events.swift
//  closet
//
//  Bidirectional calendar event sync (events + event_items + event_outfits).
//

import CoreData
import Foundation
import Supabase

extension SyncEngine {

    /// Push dirty events, pull remote (last-write-wins), then orphan cleanup.
    func syncAllEvents(userId: UUID) async throws {
        try await pushDirtyEvents(userId: userId)
        try await pullRemoteEvents(userId: userId)
        try await cleanupOrphanedEvents(userId: userId)
    }

    // MARK: - Push

    private func pushDirtyEvents(userId: UUID) async throws {
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)",
            userId.uuidString
        )

        let eventObjectIDs: [NSManagedObjectID]
        do {
            eventObjectIDs = try await performOnSyncContext { ctx in
                try ctx.fetch(request).map(\.objectID)
            }
        } catch {
            print("⚠️ Failed to fetch events for sync: \(error.localizedDescription)")
            return
        }

        if eventObjectIDs.isEmpty {
            print("ℹ️ No events need pushing")
            return
        }

        print("🔍 Found \(eventObjectIDs.count) event(s) that need pushing")
        for eventObjectID in eventObjectIDs {
            try await performOnSyncContext { ctx in
                guard let event = try ctx.existingObject(with: eventObjectID) as? Event else { return }
                if event.userId == nil || event.userId?.isEmpty == true {
                    event.userId = userId.uuidString
                }
                if (event.visibility ?? "").isEmpty {
                    event.visibility = WardrobeVisibility.private.rawValue
                }
                if ctx.hasChanges { try ctx.save() }
            }
            do {
                try await syncEvent(objectID: eventObjectID, userId: userId)
            } catch {
                let name = (try? await performOnSyncContext { ctx in
                    (try ctx.existingObject(with: eventObjectID) as? Event)?.name ?? "unnamed"
                }) ?? "unnamed"
                print("⚠️ Failed to sync event '\(name)': \(error.localizedDescription)")
            }
        }
    }

    func syncEvent(objectID: NSManagedObjectID, userId: UUID) async throws {
        struct EventSyncSnapshot {
            let eventId: UUID
            let isSoftDeleted: Bool
            let name: String?
            let notes: String?
            let location: String?
            let fullAddress: String?
            let latitude: Double
            let longitude: Double
            let startDate: Date?
            let endDate: Date?
            let date: Date?
            let time: Date?
            let timestamp: Date?
            let visibility: String
            let createdAt: Date?
            let updatedAt: Date?
            let orderedItemObjectIDs: [NSManagedObjectID]
            let orderedItemIds: [String]
            let outfitObjectIDs: [NSManagedObjectID]
            let outfitIds: Set<String>
            let unsyncedItemObjectIDs: [NSManagedObjectID]
            let unsyncedOutfitObjectIDs: [NSManagedObjectID]
        }

        let snapshot = try await performOnSyncContext { ctx -> EventSyncSnapshot? in
            guard let event = try ctx.existingObject(with: objectID) as? Event,
                  let eventId = event.id else { return nil }

            syncEventUserIdFromLinkedEntities(event)
            if event.userId == nil || event.userId?.isEmpty == true {
                event.userId = userId.uuidString
            }
            if (event.visibility ?? "").isEmpty {
                event.visibility = WardrobeVisibility.private.rawValue
            }

            var orderedItemObjectIDs: [NSManagedObjectID] = []
            var orderedItemIds: [String] = []
            var unsyncedItemObjectIDs: [NSManagedObjectID] = []
            if let ordered = event.items as? NSOrderedSet {
                for case let item as Item in ordered {
                    orderedItemObjectIDs.append(item.objectID)
                    if let id = item.id?.uuidString {
                        orderedItemIds.append(id.lowercased())
                    }
                    if item.syncedAt == nil {
                        if item.userId == nil || item.userId?.isEmpty == true {
                            item.userId = userId.uuidString
                        }
                        unsyncedItemObjectIDs.append(item.objectID)
                    }
                }
            }

            var outfitObjectIDs: [NSManagedObjectID] = []
            var outfitIds = Set<String>()
            var unsyncedOutfitObjectIDs: [NSManagedObjectID] = []
            if let outfits = event.outfits as? Set<Outfit> {
                for outfit in outfits {
                    outfitObjectIDs.append(outfit.objectID)
                    if let id = outfit.id?.uuidString {
                        outfitIds.insert(id.lowercased())
                    }
                    if outfit.syncedAt == nil, outfit.isDraft != true {
                        if outfit.userId == nil || outfit.userId?.isEmpty == true {
                            outfit.userId = userId.uuidString
                        }
                        unsyncedOutfitObjectIDs.append(outfit.objectID)
                    }
                }
            }

            if ctx.hasChanges { try ctx.save() }

            return EventSyncSnapshot(
                eventId: eventId,
                isSoftDeleted: event.isSoftDeleted,
                name: event.name,
                notes: event.notes,
                location: event.location,
                fullAddress: event.fullAddress,
                latitude: event.latitude,
                longitude: event.longitude,
                startDate: event.startDate,
                endDate: event.endDate,
                date: event.date,
                time: event.time,
                timestamp: event.timestamp,
                visibility: event.eventVisibility.rawValue,
                createdAt: event.createdAt,
                updatedAt: event.updatedAt,
                orderedItemObjectIDs: orderedItemObjectIDs,
                orderedItemIds: orderedItemIds,
                outfitObjectIDs: outfitObjectIDs,
                outfitIds: outfitIds,
                unsyncedItemObjectIDs: unsyncedItemObjectIDs,
                unsyncedOutfitObjectIDs: unsyncedOutfitObjectIDs
            )
        }

        guard let snapshot else { return }
        let eventId = snapshot.eventId

        if snapshot.isSoftDeleted {
            print("🗑️ Deleting event from Supabase: \(snapshot.name ?? eventId.uuidString)")
            try await deleteRemoteEvent(eventId: eventId)
            try await performOnSyncContext { ctx in
                guard let event = try ctx.existingObject(with: objectID) as? Event else { return }
                event.syncedAt = Date()
                try ctx.save()
            }
            schedulePurgeCallback()
            return
        }

        // Queue retry: push linked rows first so junction FKs succeed.
        for itemObjectID in snapshot.unsyncedItemObjectIDs {
            do {
                try await ensureReferencedEntitiesSynced(forItemObjectID: itemObjectID, userId: userId)
                try await syncItem(objectID: itemObjectID, userId: userId)
            } catch {
                print("⚠️ Failed to pre-sync event item: \(error.localizedDescription)")
            }
        }
        for outfitObjectID in snapshot.unsyncedOutfitObjectIDs {
            do {
                try await syncOutfit(objectID: outfitObjectID, userId: userId)
            } catch {
                print("⚠️ Failed to pre-sync event outfit: \(error.localizedDescription)")
            }
        }

        let eventData = SyncEventData(
            id: eventId.uuidString,
            userId: userId.uuidString,
            name: snapshot.name,
            notes: snapshot.notes,
            location: snapshot.location,
            fullAddress: snapshot.fullAddress,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            startDate: snapshot.startDate?.ISO8601String,
            endDate: snapshot.endDate?.ISO8601String,
            date: snapshot.date?.ISO8601String,
            time: snapshot.time?.ISO8601String,
            timestamp: snapshot.timestamp?.ISO8601String,
            visibility: snapshot.visibility,
            isSoftDeleted: false,
            createdAt: snapshot.createdAt?.ISO8601String ?? snapshot.timestamp?.ISO8601String,
            updatedAt: snapshot.updatedAt?.ISO8601String
                ?? snapshot.createdAt?.ISO8601String
                ?? Date().ISO8601String
        )

        try await (await getSupabase()).supabaseClient.from("events")
            .upsert(eventData, onConflict: "id")
            .execute()
        print("✅ Upserted event: \(snapshot.name ?? eventId.uuidString)")

        let relationshipsComplete = try await syncEventRelationships(
            orderedItemIds: snapshot.orderedItemIds,
            outfitIds: snapshot.outfitIds,
            eventId: eventId,
            allowRemoteJoinDeletes: true
        )

        // Leave dirty when joins failed so background syncAll / next edit retries.
        try await performOnSyncContext { ctx in
            guard let event = try ctx.existingObject(with: objectID) as? Event else { return }
            if relationshipsComplete {
                event.syncedAt = Date()
            } else {
                event.syncedAt = nil
                print("⏳ Event joins incomplete — queued for retry: \(snapshot.name ?? eventId.uuidString)")
            }
            try ctx.save()
        }
    }

    /// Upserts junctions; optionally diffs deletes. Returns false if any upsert failed (retry).
    @discardableResult
    func syncEventRelationships(
        orderedItemIds: [String],
        outfitIds: Set<String>,
        eventId: UUID,
        allowRemoteJoinDeletes: Bool
    ) async throws -> Bool {
        let supabase = await getSupabase()
        var allSucceeded = true

        let existingItemsResponse = try await supabase.supabaseClient.from("event_items")
            .select("item_id,sort_order")
            .eq("event_id", value: eventId.uuidString)
            .execute()
        let existingItemIds: Set<String>
        if let decoded = try? JSONDecoder().decode([EventItemResponse].self, from: existingItemsResponse.data) {
            existingItemIds = Self.normalizedUUIDStringSet(decoded.map(\.itemId))
        } else {
            existingItemIds = []
        }

        let desiredItemIds = Self.normalizedUUIDStringSet(orderedItemIds)
        if allowRemoteJoinDeletes {
            for idToDelete in existingItemIds.subtracting(desiredItemIds) {
                try? await supabase.supabaseClient.from("event_items")
                    .delete()
                    .eq("event_id", value: eventId.uuidString)
                    .eq("item_id", value: idToDelete)
                    .execute()
            }
        }

        for (index, itemId) in orderedItemIds.enumerated() {
            let junction = EventItemJunction(
                eventId: eventId.uuidString,
                itemId: itemId,
                sortOrder: index
            )
            do {
                try await supabase.supabaseClient.from("event_items")
                    .upsert(junction, onConflict: "event_id,item_id")
                    .execute()
            } catch {
                allSucceeded = false
                print("⚠️ Skipping event_items insert for item \(itemId): \(error.localizedDescription)")
            }
        }

        let existingOutfitsResponse = try await supabase.supabaseClient.from("event_outfits")
            .select("outfit_id")
            .eq("event_id", value: eventId.uuidString)
            .execute()
        let existingOutfitIds: Set<String>
        if let decoded = try? JSONDecoder().decode([EventOutfitResponse].self, from: existingOutfitsResponse.data) {
            existingOutfitIds = Self.normalizedUUIDStringSet(decoded.map(\.outfitId))
        } else {
            existingOutfitIds = []
        }

        let desiredOutfitIds = Self.normalizedUUIDStringSet(Array(outfitIds))
        if allowRemoteJoinDeletes {
            for idToDelete in existingOutfitIds.subtracting(desiredOutfitIds) {
                try? await supabase.supabaseClient.from("event_outfits")
                    .delete()
                    .eq("event_id", value: eventId.uuidString)
                    .eq("outfit_id", value: idToDelete)
                    .execute()
            }
        }

        for outfitId in desiredOutfitIds {
            let junction = EventOutfitJunction(eventId: eventId.uuidString, outfitId: outfitId)
            do {
                try await supabase.supabaseClient.from("event_outfits")
                    .upsert(junction, onConflict: "event_id,outfit_id")
                    .execute()
            } catch {
                allSucceeded = false
                print("⚠️ Skipping event_outfits insert for outfit \(outfitId): \(error.localizedDescription)")
            }
        }

        return allSucceeded
    }

    func deleteRemoteEvent(eventId: UUID) async throws {
        let supabase = await getSupabase()
        do {
            try await supabase.supabaseClient.from("event_items")
                .delete().eq("event_id", value: eventId.uuidString).execute()
        } catch {
            print("⚠️ Failed to delete event_items: \(error.localizedDescription)")
        }
        do {
            try await supabase.supabaseClient.from("event_outfits")
                .delete().eq("event_id", value: eventId.uuidString).execute()
        } catch {
            print("⚠️ Failed to delete event_outfits: \(error.localizedDescription)")
        }
        try await supabase.supabaseClient.from("events")
            .delete().eq("id", value: eventId.uuidString).execute()
    }

    // MARK: - Pull (last-write-wins)

    private func pullRemoteEvents(userId: UUID) async throws {
        let supabase = await getSupabase()
        let response = try await supabase.supabaseClient.from("events")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_soft_deleted", value: false)
            .execute()

        let remoteRows: [RemoteEventRow]
        do {
            remoteRows = try JSONDecoder().decode([RemoteEventRow].self, from: response.data)
        } catch {
            print("⚠️ Failed to decode remote events: \(error.localizedDescription)")
            return
        }

        if remoteRows.isEmpty {
            print("ℹ️ No remote events to pull")
            return
        }

        print("⬇️ Pulling \(remoteRows.count) remote event(s)")
        for row in remoteRows {
            guard let eventUUID = UUID(uuidString: row.id) else { continue }
            let remoteUpdated = Date.fromISO8601(row.updatedAt) ?? Date.fromISO8601(row.createdAt)

            let shouldApply = try await performOnSyncContext { ctx -> Bool in
                let request: NSFetchRequest<Event> = Event.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", eventUUID as CVarArg)
                request.fetchLimit = 1
                if let local = try ctx.fetch(request).first {
                    if local.isSoftDeleted { return false }
                    if let localUpdated = local.updatedAt, let remoteUpdated, localUpdated > remoteUpdated {
                        return false
                    }
                }
                return true
            }

            guard shouldApply else { continue }

            let (itemRows, outfitRows) = try await fetchRemoteEventJoins(eventId: eventUUID)
            try await applyRemoteEvent(
                row: row,
                eventUUID: eventUUID,
                userId: userId,
                itemRows: itemRows,
                outfitRows: outfitRows
            )
        }
    }

    private func fetchRemoteEventJoins(eventId: UUID) async throws -> ([EventItemResponse], [EventOutfitResponse]) {
        let supabase = await getSupabase()
        let itemsResponse = try await supabase.supabaseClient.from("event_items")
            .select("item_id,sort_order")
            .eq("event_id", value: eventId.uuidString)
            .execute()
        let itemRows = (try? JSONDecoder().decode([EventItemResponse].self, from: itemsResponse.data)) ?? []

        let outfitsResponse = try await supabase.supabaseClient.from("event_outfits")
            .select("outfit_id")
            .eq("event_id", value: eventId.uuidString)
            .execute()
        let outfitRows = (try? JSONDecoder().decode([EventOutfitResponse].self, from: outfitsResponse.data)) ?? []
        return (itemRows, outfitRows)
    }

    private func applyRemoteEvent(
        row: RemoteEventRow,
        eventUUID: UUID,
        userId: UUID,
        itemRows: [EventItemResponse],
        outfitRows: [EventOutfitResponse]
    ) async throws {
        try await performOnSyncContext { ctx in
            let request: NSFetchRequest<Event> = Event.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", eventUUID as CVarArg)
            request.fetchLimit = 1
            let event = try ctx.fetch(request).first ?? Event(context: ctx)
            if event.id == nil { event.id = eventUUID }
            event.userId = userId.uuidString
            event.name = row.name
            event.notes = row.notes
            event.location = row.location
            event.fullAddress = row.fullAddress
            event.latitude = row.latitude ?? 0
            event.longitude = row.longitude ?? 0
            event.startDate = Date.fromISO8601(row.startDate)
            event.endDate = Date.fromISO8601(row.endDate)
            event.date = Date.fromISO8601(row.date)
            event.time = Date.fromISO8601(row.time)
            event.timestamp = Date.fromISO8601(row.timestamp) ?? event.timestamp ?? Date()
            event.visibility = WardrobeVisibility(rawValue: row.visibility ?? "")?.rawValue
                ?? WardrobeVisibility.private.rawValue
            event.createdAt = Date.fromISO8601(row.createdAt) ?? event.createdAt
            event.updatedAt = Date.fromISO8601(row.updatedAt) ?? event.updatedAt
            event.isSoftDeleted = false

            let sortedItemRows = itemRows.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            var resolvedItems: [Item] = []
            var missingItem = false
            for itemRow in sortedItemRows {
                guard let itemUUID = UUID(uuidString: itemRow.itemId) else { continue }
                let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
                itemRequest.predicate = NSPredicate(
                    format: "id == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
                    itemUUID as CVarArg
                )
                itemRequest.fetchLimit = 1
                if let item = try ctx.fetch(itemRequest).first {
                    resolvedItems.append(item)
                } else {
                    missingItem = true
                }
            }

            var resolvedOutfits: [Outfit] = []
            var missingOutfit = false
            for outfitRow in outfitRows {
                guard let outfitUUID = UUID(uuidString: outfitRow.outfitId) else { continue }
                let outfitRequest: NSFetchRequest<Outfit> = Outfit.fetchRequest()
                outfitRequest.predicate = NSPredicate(
                    format: "id == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
                    outfitUUID as CVarArg
                )
                outfitRequest.fetchLimit = 1
                if let outfit = try ctx.fetch(outfitRequest).first {
                    resolvedOutfits.append(outfit)
                } else {
                    missingOutfit = true
                }
            }

            // Only replace joins when every remote FK resolves locally (avoids wiping links on partial pull).
            let joinsComplete = !missingItem && !missingOutfit
            if joinsComplete {
                if let existing = event.items as? NSOrderedSet, existing.count > 0 {
                    event.removeFromItems(existing)
                }
                for item in resolvedItems {
                    event.addToItems(item)
                }
                if let existingOutfits = event.outfits as? Set<Outfit> {
                    for outfit in existingOutfits {
                        event.removeFromOutfits(outfit)
                    }
                }
                for outfit in resolvedOutfits {
                    event.addToOutfits(outfit)
                }
                event.syncedAt = Date()
            } else {
                // Keep metadata; queue join retry without becoming push-authoritative for deletes.
                event.syncedAt = nil
                print("⏳ Pulled event \(eventUUID.uuidString) with missing local items/outfits — join retry queued")
            }

            try ctx.save()
        }
    }

    // MARK: - Orphans

    private func fetchRemoteEventIds(userId: UUID) async throws -> Set<UUID> {
        let response = try await (await getSupabase()).supabaseClient.from("events")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .execute()
        struct IdRow: Decodable { let id: String }
        let rows = try JSONDecoder().decode([IdRow].self, from: response.data)
        return Set(rows.compactMap { UUID(uuidString: $0.id) })
    }

    func cleanupOrphanedEvents(userId: UUID) async throws {
        let eventRequest: NSFetchRequest<Event> = Event.fetchRequest()
        eventRequest.predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        eventRequest.propertiesToFetch = ["id"]
        let localIds: Set<UUID> = Set(
            try await performOnSyncContext { ctx in
                try ctx.fetch(eventRequest).compactMap(\.id)
            }
        )

        let remoteIds = try await fetchRemoteEventIds(userId: userId)
        let orphanedIds = remoteIds.subtracting(localIds)
        guard !orphanedIds.isEmpty else {
            print("ℹ️ No orphaned events to clean up")
            return
        }

        print("🗑️ Found \(orphanedIds.count) orphaned event(s) in Supabase")
        for orphanedId in orphanedIds {
            do {
                try await deleteRemoteEvent(eventId: orphanedId)
                print("✅ Cleaned up orphaned event: \(orphanedId.uuidString)")
            } catch {
                print("⚠️ Failed to clean orphaned event \(orphanedId.uuidString): \(error.localizedDescription)")
            }
        }
    }
}
