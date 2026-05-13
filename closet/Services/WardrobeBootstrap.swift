//
//  WardrobeBootstrap.swift
//  closet
//
//  Ensures each signed-in user has at least one closet and one wishlist in Core Data.
//
//  Important: Previously we always *inserted* new defaults when `userId`-scoped count was 0.
//  Items often stayed on older wardrobes with `userId == nil` (seed / pre–per-user data).
//  Those wardrobes disappeared from the UI filter, so items looked "gone". We now **claim**
//  an orphan wardrobe when it is empty or all linked items belong to this user, before creating new.
//

import CoreData
import Foundation

enum WardrobeBootstrap {
    /// Creates or claims default "Closet" / "Wishlist" rows for `userId` when they have none (non–soft-deleted).
    static func ensureDefaultWardrobes(for userId: UUID, in context: NSManagedObjectContext) throws {
        let uid = userId.uuidString

        func countActive(type: String) throws -> Int {
            let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            request.predicate = NSPredicate(
                format: "type == %@ AND userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
                type,
                uid
            )
            return try context.count(for: request)
        }

        var changed: [Wardrobe] = []

        try claimOrInsertDefault(type: "closet", defaultName: "Closet", userIdString: uid, context: context, countActive: countActive, changed: &changed)
        try claimOrInsertDefault(type: "wishlist", defaultName: "Wishlist", userIdString: uid, context: context, countActive: countActive, changed: &changed)

        if !changed.isEmpty {
            try context.save()
        }

        try normalizeDefaultFlagsForUser(userIdString: uid, in: context)
        if context.hasChanges {
            try context.save()
        }

        try repairItemClosetLinksIfNeeded(userIdString: uid, in: context)
        if context.hasChanges {
            try context.save()
        }

        for wardrobe in changed {
            SyncService.shared.syncWardrobeIfNeeded(wardrobe)
        }
    }

    /// One default closet and one default wishlist per user: earliest by `timestamp`, then `createdAt`. Others `isDefault = false`.
    static func normalizeDefaultFlagsForUser(userIdString uid: String, in context: NSManagedObjectContext) throws {
        for raw in ["closet", "wishlist"] {
            let req: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            req.predicate = NSPredicate(
                format: "type ==[c] %@ AND userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
                raw,
                uid
            )
            req.sortDescriptors = [
                NSSortDescriptor(keyPath: \Wardrobe.timestamp, ascending: true),
                NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true),
            ]
            let rows = try context.fetch(req)
            guard !rows.isEmpty else { continue }
            let designated = rows[0]
            for w in rows {
                let shouldDefault = (w.objectID == designated.objectID)
                if w.isDefault != shouldDefault {
                    w.isDefault = shouldDefault
                    setUpdatedAt(w)
                }
            }
        }
    }

    /// Normalizes `isDefault` for every user that has at least one wardrobe row (one-time migration helper).
    static func normalizeAllWardrobeDefaultFlags(in context: NSManagedObjectContext) throws {
        let req = Wardrobe.fetchRequest()
        req.predicate = NSPredicate(format: "userId != nil AND userId != \"\"")
        let rows = try context.fetch(req)
        let userIds = Set(rows.compactMap { $0.userId })
        for uid in userIds {
            try normalizeDefaultFlagsForUser(userIdString: uid, in: context)
        }
    }

    /// If the user has items with no active **closet** wardrobe scoped to them, attach the primary user closet so the grid can find them.
    private static func repairItemClosetLinksIfNeeded(userIdString uid: String, in context: NSManagedObjectContext) throws {
        guard let defaultCloset = try fetchDefaultClosetForRepair(userIdString: uid, in: context) else { return }

        let itemReq: NSFetchRequest<Item> = Item.fetchRequest()
        itemReq.predicate = NSPredicate(
            format: "userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil) AND (isDraft != YES OR isDraft == nil)",
            uid
        )
        for item in try context.fetch(itemReq) {
            let wardrobes = item.wardrobes as? Set<Wardrobe> ?? []
            let hasUserCloset = wardrobes.contains { w in
                (w.type ?? "").lowercased() == "closet"
                    && w.userId == uid
                    && w.value(forKey: "isSoftDeleted") as? Bool != true
            }
            let hasUserWishlist = wardrobes.contains { w in
                (w.type ?? "").lowercased() == "wishlist"
                    && w.userId == uid
                    && w.value(forKey: "isSoftDeleted") as? Bool != true
            }
            // Wishlist-only items must stay off the closet wardrobe (see WishlistClosetRepair).
            // Without this, we would re-attach the default closet on every ensureDefaultWardrobes pass.
            if !hasUserCloset {
                if hasUserWishlist {
                    continue
                }
                item.addToWardrobes(defaultCloset)
                setUpdatedAt(item)
            }
        }
    }

    private static func claimOrInsertDefault(
        type: String,
        defaultName: String,
        userIdString uid: String,
        context: NSManagedObjectContext,
        countActive: (String) throws -> Int,
        changed: inout [Wardrobe]
    ) throws {
        guard try countActive(type) == 0 else { return }

        let orphanRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        orphanRequest.predicate = NSPredicate(
            format: "type == %@ AND (userId == nil OR userId == '') AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            type
        )
        orphanRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)]
        let orphans = try context.fetch(orphanRequest)

        for wardrobe in orphans {
            let items = wardrobe.items as? Set<Item> ?? []
            let claimable = items.isEmpty || items.allSatisfy { $0.userId == uid }
            if claimable {
                wardrobe.userId = uid
                if wardrobe.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                    wardrobe.name = defaultName
                }
                if wardrobe.timestamp == nil {
                    wardrobe.timestamp = Date()
                }
                setUpdatedAt(wardrobe)
                changed.append(wardrobe)
                return
            }
        }

        let w = Wardrobe(context: context)
        w.id = UUID()
        w.name = defaultName
        w.type = type
        w.userId = uid
        w.isDefault = false
        let now = Date()
        w.timestamp = now
        setCreatedAndUpdatedAt(w)
        changed.append(w)
    }

    /// Prefers `isDefault == YES`; otherwise earliest by `timestamp`, then `createdAt` (same rule as `normalizeDefaultFlagsForUser`).
    static func fetchPrimaryWardrobe(forType type: String, userIdString uid: String, in context: NSManagedObjectContext) throws -> Wardrobe? {
        let flagged: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        flagged.predicate = NSPredicate(
            format: "type ==[c] %@ AND userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil) AND isDefault == YES",
            type,
            uid
        )
        flagged.fetchLimit = 1
        if let w = try context.fetch(flagged).first { return w }

        let fallback: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        fallback.predicate = NSPredicate(
            format: "type ==[c] %@ AND userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            type,
            uid
        )
        fallback.sortDescriptors = [
            NSSortDescriptor(keyPath: \Wardrobe.timestamp, ascending: true),
            NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true),
        ]
        fallback.fetchLimit = 1
        return try context.fetch(fallback).first
    }

    /// Pick canonical wardrobe from an already-filtered list (e.g. UI `FetchRequest` results).
    static func primaryWardrobe(in wardrobes: [Wardrobe]) -> Wardrobe? {
        wardrobes.first(where: { $0.isDefault == true }) ?? wardrobes.first
    }

    private static func fetchDefaultClosetForRepair(userIdString uid: String, in context: NSManagedObjectContext) throws -> Wardrobe? {
        try fetchPrimaryWardrobe(forType: "closet", userIdString: uid, in: context)
    }
}
