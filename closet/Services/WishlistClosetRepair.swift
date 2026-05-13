//
//  WishlistClosetRepair.swift
//  closet
//
//  Repair: items linked to both the user's wishlist and closet wardrobes should only stay on
//  wishlist. Removes user-scoped closet links when a wishlist link is present. Safe to run repeatedly.
//

import CoreData
import Foundation

enum WishlistClosetRepair {
    /// For each of the user's items that is on a **wishlist** and also on a **closet** (same `userId`), removes the closet link(s).
    /// Returns the number of **items** that were changed.
    @discardableResult
    static func removeClosetLinksFromWishlistItems(for userId: UUID, in context: NSManagedObjectContext) throws -> Int {
        let uid = userId.uuidString

        let itemReq: NSFetchRequest<Item> = Item.fetchRequest()
        itemReq.predicate = NSPredicate(
            format: "userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            uid
        )

        var touchedItems: [Item] = []

        for item in try context.fetch(itemReq) {
            let wardrobes = item.wardrobes as? Set<Wardrobe> ?? []

            func isActiveUserWishlist(_ w: Wardrobe) -> Bool {
                (w.type ?? "").lowercased() == "wishlist"
                    && w.userId == uid
                    && w.value(forKey: "isSoftDeleted") as? Bool != true
            }

            func isActiveUserCloset(_ w: Wardrobe) -> Bool {
                (w.type ?? "").lowercased() == "closet"
                    && w.userId == uid
                    && w.value(forKey: "isSoftDeleted") as? Bool != true
            }

            let userWishlists = wardrobes.filter(isActiveUserWishlist)
            let userClosets = wardrobes.filter(isActiveUserCloset)

            guard !userWishlists.isEmpty, !userClosets.isEmpty else { continue }

            for closet in userClosets {
                item.removeFromWardrobes(closet)
            }
            setUpdatedAt(item)
            touchedItems.append(item)
        }

        if context.hasChanges {
            try context.save()
        }

        for item in touchedItems {
            SyncService.shared.syncItemIfNeeded(item)
        }

        return touchedItems.count
    }
}
