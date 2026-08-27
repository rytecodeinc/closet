import Foundation
import CoreData
import SwiftUI
import UIKit

struct OutfitSanitizerResult {
    let affectedOutfits: [Outfit]
}

enum OutfitSanitizer {
    /// Recomputes `outfit.image` for every non–soft-deleted outfit that includes `item`,
    /// using existing `transformationData` and current `Photo` data (same pipeline as delete-time regeneration).
    /// Does **not** save `context`; callers should save after mutating the item’s photos (or include this in the same save batch).
    @MainActor
    static func regenerateCollagesForOutfitsContaining(
        item: Item,
        in context: NSManagedObjectContext,
        canvasSize: CGFloat = UIScreen.main.bounds.width
    ) -> [Outfit] {
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        let containsItem = NSPredicate(format: "ANY items == %@", item)
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [containsItem, softDeleteFilter])

        do {
            let outfits = try context.fetch(request)
            guard !outfits.isEmpty else { return [] }

            var affected: [Outfit] = []
            for outfit in outfits {
                let remainingItemsSet = outfit.items as? Set<Item> ?? []
                guard !remainingItemsSet.isEmpty else { continue }

                let remainingLookup = remainingItemLookup(remainingItemsSet)
                let filteredSavedItems = sanitizedSavedItems(
                    transformationData: outfit.transformationData,
                    deletedIDs: [],
                    remainingLookup: remainingLookup
                )

                guard let uiImage = renderCollageImage(
                    remainingItemsSet: remainingItemsSet,
                    remainingLookup: remainingLookup,
                    filteredSavedItems: filteredSavedItems,
                    canvasSize: canvasSize
                ),
                let imageData = uiImage.processForStorage() else {
                    continue
                }

                outfit.image = imageData
                setUpdatedAt(outfit)
                affected.append(outfit)
            }
            return affected
        } catch {
            print("❌ Failed to fetch outfits for collage regeneration: \(error.localizedDescription)")
            return []
        }
    }

    /// Mutates outfits in `context` so they no longer reference `deletedItems`.
    /// - Removes deleted items from `outfit.items`
    /// - Removes deleted itemIDs from `outfit.transformationData`
    /// - If outfit becomes empty, soft-deletes it
    /// - Regenerates `outfit.image` collage to match remaining items + preserved transforms
    ///
    /// IMPORTANT: This does **not** save the context. Callers should save once, then sync `result.affectedOutfits`.
    @MainActor
    static func sanitizeOutfitsAfterDeleting(
        deletedItems: Set<Item>,
        in context: NSManagedObjectContext,
        canvasSize: CGFloat = UIScreen.main.bounds.width
    ) -> OutfitSanitizerResult {
        guard !deletedItems.isEmpty else { return OutfitSanitizerResult(affectedOutfits: []) }

        let deletedIDs = deletedItemIdentifiers(deletedItems)

        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.predicate = NSPredicate(format: "ANY items IN %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", deletedItems)

        do {
            let outfits = try context.fetch(request)
            guard !outfits.isEmpty else { return OutfitSanitizerResult(affectedOutfits: []) }

            var affected: [Outfit] = []
            for outfit in outfits {
                let itemsSet = outfit.items as? Set<Item> ?? []
                let itemsToRemove = deletedItems.filter { itemsSet.contains($0) }
                guard !itemsToRemove.isEmpty else { continue }

                // 1) Remove from relationship
                for item in itemsToRemove {
                    outfit.removeFromItems(item)
                }

                // 2) Purge deleted IDs from transformationData (and any IDs not in remaining items)
                let remainingItemsSet = outfit.items as? Set<Item> ?? []
                let remainingLookup = remainingItemLookup(remainingItemsSet)

                let filteredSavedItems = sanitizedSavedItems(
                    transformationData: outfit.transformationData,
                    deletedIDs: deletedIDs,
                    remainingLookup: remainingLookup
                )

                if let filteredSavedItems {
                    let encoder = JSONEncoder()
                    outfit.transformationData = try? encoder.encode(filteredSavedItems)
                }

                // 3) If empty → delete
                if (outfit.items?.count ?? 0) == 0 {
                    softDelete(outfit)
                    affected.append(outfit)
                    continue
                }

                // 4) Regenerate collage image from remaining items + transforms
                if let uiImage = renderCollageImage(
                    remainingItemsSet: remainingItemsSet,
                    remainingLookup: remainingLookup,
                    filteredSavedItems: filteredSavedItems,
                    canvasSize: canvasSize
                ),
                let imageData = uiImage.processForStorage() {
                    outfit.image = imageData
                }

                setUpdatedAt(outfit)
                affected.append(outfit)
            }

            return OutfitSanitizerResult(affectedOutfits: affected)
        } catch {
            print("❌ Failed to sanitize outfits after deleting items: \(error.localizedDescription)")
            return OutfitSanitizerResult(affectedOutfits: [])
        }
    }

    // MARK: - Public collage render

    /// Renders the outfit collage from current `items` + `transformationData` (same pipeline as delete-time regen).
    @MainActor
    static func collageImage(
        for outfit: Outfit,
        canvasSize: CGFloat = UIScreen.main.bounds.width
    ) -> UIImage? {
        let remainingItemsSet = outfit.items as? Set<Item> ?? []
        guard !remainingItemsSet.isEmpty else { return nil }
        let remainingLookup = remainingItemLookup(remainingItemsSet)
        let filteredSavedItems = sanitizedSavedItems(
            transformationData: outfit.transformationData,
            deletedIDs: [],
            remainingLookup: remainingLookup
        )
        return renderCollageImage(
            remainingItemsSet: remainingItemsSet,
            remainingLookup: remainingLookup,
            filteredSavedItems: filteredSavedItems,
            canvasSize: canvasSize
        )
    }

    // MARK: - Identifiers

    private static func deletedItemIdentifiers(_ items: Set<Item>) -> Set<String> {
        var ids: Set<String> = []
        for item in items {
            if let uuid = item.id?.uuidString { ids.insert(uuid) }
            ids.insert(item.objectID.uriRepresentation().absoluteString)
        }
        return ids
    }

    /// Lookup by both UUID string and ObjectID URI string.
    private static func remainingItemLookup(_ items: Set<Item>) -> [String: Item] {
        var lookup: [String: Item] = [:]
        for item in items {
            if let uuid = item.id?.uuidString { lookup[uuid] = item }
            lookup[item.objectID.uriRepresentation().absoluteString] = item
        }
        return lookup
    }

    // MARK: - transformationData sanitization

    private static func sanitizedSavedItems(
        transformationData: Data?,
        deletedIDs: Set<String>,
        remainingLookup: [String: Item]
    ) -> [SavedOutfitItem]? {
        guard let transformationData else { return nil }
        let decoder = JSONDecoder()
        guard let savedItems = try? decoder.decode([SavedOutfitItem].self, from: transformationData) else { return nil }

        let filtered = savedItems.filter { saved in
            if deletedIDs.contains(saved.itemID) { return false }
            return remainingLookup[saved.itemID] != nil
        }

        return filtered
    }

    // MARK: - Collage rendering

    @MainActor
    private static func renderCollageImage(
        remainingItemsSet: Set<Item>,
        remainingLookup: [String: Item],
        filteredSavedItems: [SavedOutfitItem]?,
        canvasSize: CGFloat
    ) -> UIImage? {
        // Reconstruct render order + transforms from saved items if present.
        var renderItems: [(item: Item, position: CGPoint?, scale: CGFloat, rotation: Double, zIndex: Int)] = []

        if let filteredSavedItems, !filteredSavedItems.isEmpty {
            for saved in filteredSavedItems {
                guard let item = remainingLookup[saved.itemID] else { continue }
                renderItems.append((
                    item: item,
                    position: CGPoint(x: saved.positionX, y: saved.positionY),
                    scale: saved.scale,
                    rotation: saved.rotation,
                    zIndex: saved.zIndex
                ))
            }
        }

        // If there were remaining items not represented in transformationData, append them.
        let represented = Set(renderItems.map { $0.item.objectID })
        var nextZ = (renderItems.map(\.zIndex).max() ?? -1) + 1
        for item in remainingItemsSet where !represented.contains(item.objectID) {
            renderItems.append((item: item, position: nil, scale: 1.0, rotation: 0.0, zIndex: nextZ))
            nextZ += 1
        }

        guard !renderItems.isEmpty else { return nil }

        let center = CGPoint(x: canvasSize / 2, y: canvasSize / 2)
        let outfitItems: [OutfitItem] = renderItems
            .sorted(by: { $0.zIndex < $1.zIndex })
            .map { entry in
                let bounds = PhotoContentBounds.contentBounds(for: entry.item)
                return OutfitItem(
                    item: entry.item,
                    position: entry.position ?? center,
                    displaySize: OutfitItem.defaultDisplaySize(canvasSize: canvasSize, contentAspect: bounds.aspectRatio),
                    scale: entry.scale,
                    rotation: entry.rotation,
                    zIndex: entry.zIndex,
                    contentBounds: bounds
                )
            }

        let captureView = Canvas { ctx, _ in
            for outfitItem in outfitItems.sorted(by: { $0.zIndex < $1.zIndex }) {
                guard let primaryPhoto = (outfitItem.item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                      let photoData = primaryPhoto.data,
                      let uiImage = UIImage(data: photoData) else { continue }

                let center = outfitItem.position
                let scaledW = outfitItem.displaySize.width * outfitItem.scale
                let scaledH = outfitItem.displaySize.height * outfitItem.scale

                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: Angle.degrees(outfitItem.rotation))

                let drawImage = uiImage.cropped(toNormalizedBounds: outfitItem.contentBounds) ?? uiImage
                let drawRect = CGRect(x: -scaledW / 2, y: -scaledH / 2, width: scaledW, height: scaledH)
                ctx.draw(Image(uiImage: drawImage).resizable(), in: drawRect)

                ctx.rotate(by: Angle.degrees(-outfitItem.rotation))
                ctx.translateBy(x: -center.x, y: -center.y)
            }
        }
        .frame(width: canvasSize, height: canvasSize)

        let renderer = ImageRenderer(content: captureView)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

