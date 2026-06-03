//
//  SyncEngine+Relationships
//  closet
//

import CoreData
import Foundation
import Supabase
import UIKit


extension SyncEngine {
    func syncItemRelationships(itemObjectID: NSManagedObjectID, userId: UUID) async throws {
        struct Snap {
            let itemId: UUID
            let name: String
            let colors: Set<String>
            let seasons: Set<String>
            let tags: Set<String>
            let wardrobes: Set<String>
            let pairs: Set<String>
        }
        guard let snap = try await performOnSyncContext({ ctx -> Snap? in
            guard let item = try ctx.existingObject(with: itemObjectID) as? Item, let id = item.id else { return nil }
            let colors = Set((item.colors as? Set<AppColor> ?? []).compactMap { $0.id?.uuidString })
            let seasons = Set((item.seasons as? Set<Season> ?? []).compactMap { $0.id?.uuidString })
            let tags = Set((item.tags as? Set<Tag> ?? []).compactMap { $0.id?.uuidString })
            let wardrobes = Set((item.wardrobes as? Set<Wardrobe> ?? []).compactMap { $0.id?.uuidString })
            let pairs = Set((item.pairedItems as? Set<Item> ?? []).compactMap { $0.id?.uuidString })
            return Snap(itemId: id, name: item.name ?? "unnamed", colors: colors, seasons: seasons, tags: tags, wardrobes: wardrobes, pairs: pairs)
        }) else { return }
        let itemId = snap.itemId
        let itemName = snap.name
        var currentColorIds = snap.colors
        var currentSeasonIds = snap.seasons
        var currentTagIds = snap.tags
        var currentWardrobeIds = snap.wardrobes
        var currentPairIds = snap.pairs

        
        // Sync item_colors with proper deletion handling
        print("🎨 Starting color sync for item: \(itemName) (ID: \(itemId.uuidString))")
        
        // STEP 2: Get what colors currently exist in Supabase (BEFORE making any changes)
        let existingColorsResponse = try await (await getSupabase()).supabaseClient.from("item_colors")
            .select("color_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let colorsData: Data = existingColorsResponse.data
        let existingColorIds: Set<String>
        if let existingColors = try? JSONDecoder().decode([ItemColorResponse].self, from: colorsData) {
            existingColorIds = Set(existingColors.compactMap { $0.colorId })
            print("🎨 Supabase shows \(existingColorIds.count) existing colors")
        } else {
            existingColorIds = Set()
            print("🎨 Supabase shows 0 existing colors (or failed to decode)")
        }
        
        // STEP 3: Delete colors that no longer exist in Core Data
        let colorsToDelete = existingColorIds.subtracting(currentColorIds)
        if !colorsToDelete.isEmpty {
            print("🗑️ Deleting \(colorsToDelete.count) orphaned colors from Supabase")
            for colorIdToDelete in colorsToDelete {
                do {
                    try await (await getSupabase()).supabaseClient.from("item_colors")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("color_id", value: colorIdToDelete)
                        .execute()
                    print("✅ Deleted color: \(colorIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete color \(colorIdToDelete): \(error)")
                }
            }
        } else {
            print("🎨 No orphaned colors to delete")
        }
        
        // STEP 4: Now sync current colors (upsert new/existing)
        if !currentColorIds.isEmpty {
            print("🎨 Upserting \(currentColorIds.count) current colors to Supabase")
            for colorId in currentColorIds {
                let junctionData = ItemColorJunction(itemId: itemId.uuidString, colorId: colorId)
                try await (await getSupabase()).supabaseClient.from("item_colors")
                    .upsert(junctionData, onConflict: "item_id,color_id")
                    .execute()
            }
            print("✅ Finished syncing \(currentColorIds.count) colors")
        } else {
            print("🎨 No colors in Core Data")
        }
        
        // Sync item_seasons with proper deletion handling
        print("🍂 Starting season sync for item: \(itemName) (ID: \(itemId.uuidString))")
        
        // STEP 2: Get what seasons currently exist in Supabase (BEFORE making any changes)
        let existingSeasonsResponse = try await (await getSupabase()).supabaseClient.from("item_seasons")
            .select("season_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let seasonsData: Data = existingSeasonsResponse.data
        let existingSeasonIds: Set<String>
        if let existingSeasons = try? JSONDecoder().decode([ItemSeasonResponse].self, from: seasonsData) {
            existingSeasonIds = Set(existingSeasons.compactMap { $0.seasonId })
            print("🍂 Supabase shows \(existingSeasonIds.count) existing seasons")
        } else {
            existingSeasonIds = Set()
            print("🍂 Supabase shows 0 existing seasons (or failed to decode)")
        }
        
        // STEP 3: Delete seasons that no longer exist in Core Data
        let seasonsToDelete = existingSeasonIds.subtracting(currentSeasonIds)
        if !seasonsToDelete.isEmpty {
            print("🗑️ Deleting \(seasonsToDelete.count) orphaned seasons from Supabase")
            for seasonIdToDelete in seasonsToDelete {
                do {
                    try await (await getSupabase()).supabaseClient.from("item_seasons")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("season_id", value: seasonIdToDelete)
                        .execute()
                    print("✅ Deleted season: \(seasonIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete season \(seasonIdToDelete): \(error)")
                }
            }
        } else {
            print("🍂 No orphaned seasons to delete")
        }
        
        // STEP 4: Now sync current seasons (upsert new/existing)
        if !currentSeasonIds.isEmpty {
            print("🍂 Upserting \(currentSeasonIds.count) current seasons to Supabase")
            for seasonId in currentSeasonIds {
                let junctionData = ItemSeasonJunction(itemId: itemId.uuidString, seasonId: seasonId)
                try await (await getSupabase()).supabaseClient.from("item_seasons")
                    .upsert(junctionData, onConflict: "item_id,season_id")
                    .execute()
            }
            print("✅ Finished syncing \(currentSeasonIds.count) seasons")
        } else {
            print("🍂 No seasons in Core Data")
        }
        
        // Sync item_tags with proper deletion handling
        print("🏷️ Starting tag sync for item: \(itemName) (ID: \(itemId.uuidString))")
        
        // STEP 2: Get what tags currently exist in Supabase (BEFORE making any changes)
        let existingTagsResponse = try await (await getSupabase()).supabaseClient.from("item_tags")
            .select("tag_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let tagsData: Data = existingTagsResponse.data
        let existingTagIds: Set<String>
        if let existingTags = try? JSONDecoder().decode([ItemTagResponse].self, from: tagsData) {
            existingTagIds = Set(existingTags.compactMap { $0.tagId })
            print("🏷️ Supabase shows \(existingTagIds.count) existing tags")
        } else {
            existingTagIds = Set()
            print("🏷️ Supabase shows 0 existing tags (or failed to decode)")
        }
        
        // STEP 3: Delete tags that no longer exist in Core Data
        let tagsToDelete = existingTagIds.subtracting(currentTagIds)
        if !tagsToDelete.isEmpty {
            print("🗑️ Deleting \(tagsToDelete.count) orphaned tags from Supabase")
            for tagIdToDelete in tagsToDelete {
                do {
                    try await (await getSupabase()).supabaseClient.from("item_tags")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("tag_id", value: tagIdToDelete)
                        .execute()
                    print("✅ Deleted tag: \(tagIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete tag \(tagIdToDelete): \(error)")
                }
            }
        } else {
            print("🏷️ No orphaned tags to delete")
        }
        
        // STEP 4: Now sync current tags (upsert new/existing)
        if !currentTagIds.isEmpty {
            print("🏷️ Upserting \(currentTagIds.count) current tags to Supabase")
            for tagId in currentTagIds {
                let junctionData = ItemTagJunction(itemId: itemId.uuidString, tagId: tagId)
                try await (await getSupabase()).supabaseClient.from("item_tags")
                    .upsert(junctionData, onConflict: "item_id,tag_id")
                    .execute()
            }
            print("✅ Finished syncing \(currentTagIds.count) tags")
        } else {
            print("🏷️ No tags in Core Data")
        }
        
        // Sync item_wardrobes with proper deletion handling
        print("👔 Starting wardrobe sync for item: \(itemName) (ID: \(itemId.uuidString))")
        
        // STEP 2: Get what wardrobes currently exist in Supabase (BEFORE making any changes)
        let existingWardrobesResponse = try await (await getSupabase()).supabaseClient.from("item_wardrobes")
            .select("wardrobe_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let wardrobesData: Data = existingWardrobesResponse.data
        let existingWardrobeIds: Set<String>
        if let existingWardrobes = try? JSONDecoder().decode([ItemWardrobeResponse].self, from: wardrobesData) {
            existingWardrobeIds = Set(existingWardrobes.compactMap { $0.wardrobeId })
            print("👔 Supabase shows \(existingWardrobeIds.count) existing wardrobes")
        } else {
            existingWardrobeIds = Set()
            print("👔 Supabase shows 0 existing wardrobes (or failed to decode)")
        }
        
        // STEP 3: Delete wardrobes that no longer exist in Core Data
        let wardrobesToDelete = existingWardrobeIds.subtracting(currentWardrobeIds)
        if !wardrobesToDelete.isEmpty {
            print("🗑️ Deleting \(wardrobesToDelete.count) orphaned wardrobes from Supabase")
            for wardrobeIdToDelete in wardrobesToDelete {
                do {
                    try await (await getSupabase()).supabaseClient.from("item_wardrobes")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("wardrobe_id", value: wardrobeIdToDelete)
                        .execute()
                    print("✅ Deleted wardrobe: \(wardrobeIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete wardrobe \(wardrobeIdToDelete): \(error)")
                }
            }
        } else {
            print("👔 No orphaned wardrobes to delete")
        }
        
        // STEP 4: Now sync current wardrobes (upsert new/existing)
        if !currentWardrobeIds.isEmpty {
            print("👔 Upserting \(currentWardrobeIds.count) current wardrobes to Supabase")
            for wardrobeId in currentWardrobeIds {
                let junctionData = ItemWardrobeJunction(itemId: itemId.uuidString, wardrobeId: wardrobeId)
                try await (await getSupabase()).supabaseClient.from("item_wardrobes")
                    .upsert(junctionData, onConflict: "item_id,wardrobe_id")
                    .execute()
            }
            print("✅ Finished syncing \(currentWardrobeIds.count) wardrobes")
        } else {
            print("👔 No wardrobes in Core Data")
        }
        
        // Sync item_pairs with proper deletion handling
        // Note: Pairs are bidirectional in Core Data, but we store them bidirectionally in Supabase
        // to make queries easier. We sync both directions: (item_id, paired_item_id) and (paired_item_id, item_id)
        print("🔗 Starting pair sync for item: \(itemName) (ID: \(itemId.uuidString))")
        
        // STEP 2: Get what pairs currently exist in Supabase (BEFORE making any changes)
        let existingPairsResponse = try await (await getSupabase()).supabaseClient.from("item_pairs")
            .select("paired_item_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let data: Data = existingPairsResponse.data
        let existingPairedItemIds: Set<String>
        if let existingPairs = try? JSONDecoder().decode([ItemPairResponse].self, from: data) {
            existingPairedItemIds = Set(existingPairs.compactMap { $0.pairedItemId })
            print("🔗 Supabase shows \(existingPairedItemIds.count) existing pairs")
            for (idx, pairedId) in existingPairedItemIds.enumerated() {
                print("   Existing pair #\(idx + 1): \(pairedId)")
            }
        } else {
            existingPairedItemIds = Set()
            print("🔗 Supabase shows 0 existing pairs (or failed to decode)")
        }
        
        // STEP 3: Delete pairs that no longer exist in Core Data
        let pairsToDelete = existingPairedItemIds.subtracting(currentPairIds)
        if !pairsToDelete.isEmpty {
            print("🗑️ Deleting \(pairsToDelete.count) orphaned pairs from Supabase")
            for pairedItemIdToDelete in pairsToDelete {
                print("🗑️ Deleting pair: \(itemId.uuidString) <-> \(pairedItemIdToDelete)")
                
                // Delete direction 1: item -> pairedItem
                do {
                    try await (await getSupabase()).supabaseClient.from("item_pairs")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("paired_item_id", value: pairedItemIdToDelete)
                        .execute()
                    print("✅ Deleted: \(itemId.uuidString) -> \(pairedItemIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete pair \(itemId.uuidString) -> \(pairedItemIdToDelete): \(error)")
                }
                
                // Delete direction 2: pairedItem -> item
                do {
                    try await (await getSupabase()).supabaseClient.from("item_pairs")
                        .delete()
                        .eq("item_id", value: pairedItemIdToDelete)
                        .eq("paired_item_id", value: itemId.uuidString)
                        .execute()
                    print("✅ Deleted: \(pairedItemIdToDelete) -> \(itemId.uuidString)")
                } catch {
                    print("⚠️ Failed to delete pair \(pairedItemIdToDelete) -> \(itemId.uuidString): \(error)")
                }
            }
        } else {
            print("🔗 No orphaned pairs to delete")
        }
        
        // STEP 4: Now sync current pairs (upsert new/existing)
        if !currentPairIds.isEmpty {
            print("🔗 Upserting \(currentPairIds.count) current pairs to Supabase")
            let pairedItemArray = Array(currentPairIds)
            
            for (index, pairedItemId) in pairedItemArray.enumerated() {
                print("🔗 Processing pair #\(index + 1): \(itemId.uuidString) <-> \(pairedItemId)")
                
                // Sync both directions
                // Direction 1: item -> pairedItem
                let junctionData1 = ItemPairJunction(
                    itemId: itemId.uuidString,
                    pairedItemId: pairedItemId
                )
                do {
                    try await (await getSupabase()).supabaseClient.from("item_pairs")
                        .upsert(junctionData1, onConflict: "item_id,paired_item_id")
                        .execute()
                    print("✅ Upserted: \(itemId.uuidString) -> \(pairedItemId)")
                } catch {
                    print("❌ Failed to upsert pair \(itemId.uuidString) -> \(pairedItemId): \(error)")
                    print("❌ Error: \(error.localizedDescription)")
                }
                
                // Direction 2: pairedItem -> item (bidirectional)
                let junctionData2 = ItemPairJunction(
                    itemId: pairedItemId,
                    pairedItemId: itemId.uuidString
                )
                do {
                    try await (await getSupabase()).supabaseClient.from("item_pairs")
                        .upsert(junctionData2, onConflict: "item_id,paired_item_id")
                        .execute()
                    print("✅ Upserted: \(pairedItemId) -> \(itemId.uuidString)")
                } catch {
                    print("❌ Failed to upsert pair \(pairedItemId) -> \(itemId.uuidString): \(error)")
                    print("❌ Error: \(error.localizedDescription)")
                }
            }
            
            print("✅ Finished syncing \(currentPairIds.count) pairs")
        } else {
            // No paired items in Core Data
            print("🔗 No paired items in Core Data")
            
            // Delete all pairs for this item if any exist in Supabase
            if !existingPairedItemIds.isEmpty {
                print("🗑️ Deleting all \(existingPairedItemIds.count) pairs from Supabase")
                do {
                    try await (await getSupabase()).supabaseClient.from("item_pairs")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .execute()
                    
                    try await (await getSupabase()).supabaseClient.from("item_pairs")
                        .delete()
                        .eq("paired_item_id", value: itemId.uuidString)
                        .execute()
                    print("✅ Deleted all pairs for item")
                } catch {
                    print("⚠️ Failed to delete all pairs: \(error)")
                }
            }
        }
    }
    
    func syncItemRelationships(_ item: Item, userId: UUID) async throws {
        try await syncItemRelationships(itemObjectID: item.objectID, userId: userId)
    }

    /// Syncs item links with proper deletion handling
    func syncItemLinks(itemObjectID: NSManagedObjectID, itemId: UUID, userId: UUID) async throws {
        let itemName = try await withSyncItem(itemObjectID) { $0.name ?? "unnamed" }
        let currentLinkIds = try await withSyncItem(itemObjectID) { item -> Set<String> in
            Set((item.links as? Set<Link> ?? []).compactMap { $0.id?.uuidString })
        }
        let linkObjectIDs = try await withSyncItem(itemObjectID) { item -> [NSManagedObjectID] in
            (item.links as? Set<Link>)?.map { $0.objectID } ?? []
        }

        print("🔗 Starting link sync for item: \(itemName) (ID: \(itemId.uuidString))")
        

        // STEP 2: Get what links currently exist in Supabase (BEFORE making any changes)
        let existingLinksResponse = try await (await getSupabase()).supabaseClient.from("item_links")
            .select("id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let data: Data = existingLinksResponse.data
        let existingLinkIds: Set<String>
        if let existingLinks = try? JSONDecoder().decode([ItemLinkResponse].self, from: data) {
            existingLinkIds = Set(existingLinks.compactMap { $0.id })
            print("🔗 Supabase shows \(existingLinkIds.count) existing links")
        } else {
            existingLinkIds = Set()
            print("🔗 Supabase shows 0 existing links (or failed to decode)")
        }
        
        // STEP 3: Delete links that no longer exist in Core Data
        let linksToDelete = existingLinkIds.subtracting(currentLinkIds)
        if !linksToDelete.isEmpty {
            print("🗑️ Deleting \(linksToDelete.count) orphaned links from Supabase")
            for linkIdToDelete in linksToDelete {
                do {
                    try await (await getSupabase()).supabaseClient.from("item_links")
                        .delete()
                        .eq("id", value: linkIdToDelete)
                        .execute()
                    print("✅ Deleted link: \(linkIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete link \(linkIdToDelete): \(error)")
                }
            }
        } else {
            print("🔗 No orphaned links to delete")
        }
        
        // STEP 4: Now sync current links (upsert new/existing)
        if !linkObjectIDs.isEmpty {
            print("🔗 Upserting \(linkObjectIDs.count) current links to Supabase")
            for linkObjectID in linkObjectIDs {
                try await syncLink(objectID: linkObjectID, itemId: itemId, userId: userId)
            }
            print("✅ Finished syncing \(linkObjectIDs.count) links")
        } else {
            print("🔗 No links in Core Data")
        }
    }

    func syncItemLinks(_ item: Item, itemId: UUID, userId: UUID) async throws {
        try await syncItemLinks(itemObjectID: item.objectID, itemId: itemId, userId: userId)
    }

    /// Syncs item price
    func syncPrice(objectID: NSManagedObjectID, itemId: UUID, userId: UUID) async throws {
        let priceData = try await performOnSyncContext { ctx -> SyncPriceData? in
            guard let price = try ctx.existingObject(with: objectID) as? Price else { return nil }
            let amount: Decimal
            if let nsDecimal = price.amount { amount = nsDecimal as Decimal } else { amount = 0.0 }
            return SyncPriceData(itemId: itemId.uuidString, amount: amount, currency: price.currency ?? "USD")
        }
        guard let priceData else { return }
        try await (await getSupabase()).supabaseClient.from("item_prices")
            .upsert(priceData, onConflict: "item_id")
            .execute()
    }

    func syncPrice(_ price: Price, itemId: UUID, userId: UUID) async throws {
        try await syncPrice(objectID: price.objectID, itemId: itemId, userId: userId)
    }

    func syncLink(objectID: NSManagedObjectID, itemId: UUID, userId: UUID) async throws {
        let linkData = try await performOnSyncContext { ctx -> SyncLinkData? in
            guard let link = try ctx.existingObject(with: objectID) as? Link, let linkId = link.id else { return nil }
            return SyncLinkData(
                id: linkId.uuidString,
                itemId: itemId.uuidString,
                name: link.name,
                url: link.url?.absoluteString
            )
        }
        guard let linkData else { return }
        try await (await getSupabase()).supabaseClient.from("item_links")
            .upsert(linkData, onConflict: "id")
            .execute()
    }

    func syncLink(_ link: Link, itemId: UUID, userId: UUID) async throws {
        try await syncLink(objectID: link.objectID, itemId: itemId, userId: userId)
    }
}
