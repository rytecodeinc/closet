//
//  SyncEngine+Packing.swift
//  closet
//

import CoreData
import Foundation

extension SyncEngine {

    /// Last-write-wins upsert of the whole packing checklist document.
    func syncPackingChecklistDocument(objectID: NSManagedObjectID, userId: UUID) async throws {
        let payload = try await performOnSyncContext { ctx -> SyncPackingChecklistDocumentData? in
            guard let doc = try ctx.existingObject(with: objectID) as? PackingChecklistDocument,
                  let id = doc.id,
                  let wardrobeId = doc.wardrobe?.id,
                  let bodyData = doc.bodyJSON,
                  let body = PackingChecklistDocumentCodec.decode(bodyData) else { return nil }
            if doc.userId == nil || doc.userId?.isEmpty == true {
                doc.userId = userId.uuidString
                try ctx.save()
            }
            return SyncPackingChecklistDocumentData(
                id: id.uuidString,
                userId: userId.uuidString,
                wardrobeId: wardrobeId.uuidString,
                kind: Int(doc.kind),
                body: body,
                createdAt: doc.createdAt?.ISO8601String,
                updatedAt: doc.updatedAt?.ISO8601String ?? doc.createdAt?.ISO8601String
            )
        }
        guard let payload else { return }
        let supabase = await getSupabase()
        try await supabase.supabaseClient.from("packing_checklist_documents")
            .upsert(payload, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let doc = try ctx.existingObject(with: objectID) as? PackingChecklistDocument else { return }
            doc.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncPackingChecklistDocumentIfNeeded(objectID: NSManagedObjectID, userId: UUID) async throws {
        let needsSync = try await performOnSyncContext { ctx -> Bool in
            guard let doc = try ctx.existingObject(with: objectID) as? PackingChecklistDocument,
                  doc.wardrobe?.id != nil else { return false }
            if doc.syncedAt == nil { return true }
            if let updatedAt = doc.updatedAt, let syncedAt = doc.syncedAt {
                return updatedAt >= syncedAt
            }
            return false
        }
        guard needsSync else { return }
        try await syncPackingChecklistDocument(objectID: objectID, userId: userId)
    }

    func syncPackingChecklistSection(objectID: NSManagedObjectID, userId: UUID) async throws {
        let payload = try await performOnSyncContext { ctx -> SyncPackingChecklistSectionData? in
            guard let section = try ctx.existingObject(with: objectID) as? PackingChecklistSection,
                  let id = section.id,
                  let wardrobeId = section.wardrobe?.id else { return nil }
            let title = (section.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return SyncPackingChecklistSectionData(
                id: id.uuidString,
                userId: userId.uuidString,
                wardrobeId: wardrobeId.uuidString,
                kind: Int(section.kind),
                title: title,
                sortIndex: Int(section.sortIndex),
                createdAt: section.createdAt?.ISO8601String,
                updatedAt: section.updatedAt?.ISO8601String ?? section.createdAt?.ISO8601String
            )
        }
        guard let payload else { return }
        let supabase = await getSupabase()
        try await supabase.supabaseClient.from("packing_checklist_sections")
            .upsert(payload, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let section = try ctx.existingObject(with: objectID) as? PackingChecklistSection else { return }
            section.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncPackingChecklistRow(objectID: NSManagedObjectID, userId: UUID, checklistText: String) async throws {
        let payload = try await performOnSyncContext { ctx -> SyncPackingChecklistItemData? in
            guard let row = try ctx.existingObject(with: objectID) as? PackingChecklistItem,
                  let id = row.id,
                  let wardrobeId = row.wardrobe?.id else { return nil }
            return SyncPackingChecklistItemData(
                id: id.uuidString,
                userId: userId.uuidString,
                wardrobeId: wardrobeId.uuidString,
                sectionId: row.section?.id?.uuidString,
                kind: Int(row.kind),
                checklistText: checklistText,
                isCompleted: row.isCompleted,
                sortIndex: Int(row.sortIndex),
                createdAt: row.createdAt?.ISO8601String,
                updatedAt: row.updatedAt?.ISO8601String ?? row.createdAt?.ISO8601String
            )
        }
        guard let payload else { return }
        let supabase = await getSupabase()
        try await supabase.supabaseClient.from("packing_checklist_items")
            .upsert(payload, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let row = try ctx.existingObject(with: objectID) as? PackingChecklistItem else { return }
            row.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncPackingChecklistItemIfNeeded(objectID: NSManagedObjectID, rowId: UUID, userId: UUID) async throws {
        let rowState = try await performOnSyncContext { ctx -> (needsSync: Bool, trimmedText: String, wardrobeObjectID: NSManagedObjectID?, sectionObjectID: NSManagedObjectID?, hadSyncedAt: Bool)? in
            let request: NSFetchRequest<PackingChecklistItem> = PackingChecklistItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", rowId as CVarArg)
            request.fetchLimit = 1
            guard let refreshed = try ctx.fetch(request).first else { return nil }
            guard refreshed.wardrobe != nil, refreshed.wardrobe?.id != nil else { return nil }

            if refreshed.userId == nil || refreshed.userId?.isEmpty == true {
                refreshed.userId = userId.uuidString
                try ctx.save()
            }

            let needsSync: Bool
            if refreshed.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = refreshed.updatedAt, let syncedAt = refreshed.syncedAt {
                needsSync = updatedAt >= syncedAt
            } else {
                needsSync = false
            }

            return (
                needsSync,
                (refreshed.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                refreshed.wardrobe?.objectID,
                refreshed.section?.objectID,
                refreshed.syncedAt != nil
            )
        }

        guard let rowState else {
            print("⚠️ Packing checklist row missing wardrobe; skip sync \(rowId.uuidString)")
            return
        }
        guard rowState.needsSync else { return }

        let supabase = await getSupabase()

        if rowState.trimmedText.isEmpty {
            if rowState.hadSyncedAt {
                try await supabase.supabaseClient.from("packing_checklist_items")
                    .delete()
                    .eq("id", value: rowId.uuidString)
                    .execute()
                print("✅ Removed empty packing_checklist_items row \(rowId.uuidString) from Supabase")
            }
            try await performOnSyncContext { ctx in
                guard let refreshed = try ctx.existingObject(with: objectID) as? PackingChecklistItem else { return }
                refreshed.syncedAt = Date()
                try ctx.save()
            }
            return
        }

        if let wardrobeObjectID = rowState.wardrobeObjectID {
            let wardrobeNeedsPush = try await performOnSyncContext { ctx -> Bool in
                guard let wardrobe = try ctx.existingObject(with: wardrobeObjectID) as? Wardrobe else { return false }
                if wardrobe.syncedAt == nil { return true }
                if let wu = wardrobe.updatedAt, let ws = wardrobe.syncedAt {
                    return wu >= ws
                }
                return false
            }
            if wardrobeNeedsPush {
                try await syncWardrobe(objectID: wardrobeObjectID, userId: userId)
            }
        }
        if let sectionObjectID = rowState.sectionObjectID {
            try await syncPackingChecklistSection(objectID: sectionObjectID, userId: userId)
        }
        try await syncPackingChecklistRow(objectID: objectID, userId: userId, checklistText: rowState.trimmedText)
    }

    func syncPackingChecklistSectionIfNeeded(objectID: NSManagedObjectID, sectionId: UUID, userId: UUID) async throws {
        let needsSync = try await performOnSyncContext { ctx -> Bool in
            let request: NSFetchRequest<PackingChecklistSection> = PackingChecklistSection.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", sectionId as CVarArg)
            request.fetchLimit = 1
            guard let refreshed = try ctx.fetch(request).first,
                  refreshed.wardrobe?.id != nil else { return false }

            if refreshed.userId == nil || refreshed.userId?.isEmpty == true {
                refreshed.userId = userId.uuidString
                try ctx.save()
            }

            if refreshed.syncedAt == nil { return true }
            if let updatedAt = refreshed.updatedAt, let syncedAt = refreshed.syncedAt {
                return updatedAt >= syncedAt
            }
            return false
        }

        guard needsSync else { return }
        try await syncPackingChecklistSection(objectID: objectID, userId: userId)
    }
}
