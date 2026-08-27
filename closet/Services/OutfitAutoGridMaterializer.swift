//
//  OutfitAutoGridMaterializer.swift
//  closet
//
//  Builds (or reuses) a closet outfit from a set of items using the same auto-grid
//  packing as OutfitAddView, then renders a collage for storage/sync.
//

import CoreData
import SwiftUI
import UIKit

enum OutfitAutoGridMaterializer {

    /// Returns an existing non-draft outfit with the exact same active item set, or creates
    /// a new auto-gridded collage outfit in the closet.
    @MainActor
    @discardableResult
    static func matchingOrCreatingOutfit(
        from items: [Item],
        userId: String,
        in context: NSManagedObjectContext,
        canvasSize: CGFloat = UIScreen.main.bounds.width
    ) -> Outfit? {
        let uniqueItems = deduplicatedActiveItems(items)
        guard !uniqueItems.isEmpty else { return nil }

        let itemIds = uniqueItems.compactMap(\.id)
        guard !itemIds.isEmpty else { return nil }

        if let existing = findDuplicateOutfit(
            matchingItemIds: itemIds,
            userId: userId,
            in: context
        ) {
            return existing
        }

        return createAutoGridOutfit(
            items: uniqueItems,
            userId: userId,
            in: context,
            canvasSize: canvasSize
        )
    }

    // MARK: - Create

    @MainActor
    private static func createAutoGridOutfit(
        items: [Item],
        userId: String,
        in context: NSManagedObjectContext,
        canvasSize: CGFloat
    ) -> Outfit? {
        let slots = autoGridSlots(items: items, canvasSize: canvasSize)
        guard !slots.isEmpty else { return nil }

        let outfit = Outfit(context: context)
        outfit.id = UUID()
        outfit.userId = userId
        outfit.isDraft = false
        outfit.isSoftDeleted = false
        outfit.timestamp = Date()
        setCreatedAndUpdatedAt(outfit)

        for slot in slots {
            outfit.addToItems(slot.item)
        }

        let savedItems = slots.map { slot in
            SavedOutfitItem(
                itemID: slot.item.id?.uuidString ?? "",
                positionX: slot.position.x,
                positionY: slot.position.y,
                scale: slot.scale,
                rotation: slot.rotation,
                zIndex: slot.zIndex
            )
        }
        if let data = try? JSONEncoder().encode(savedItems) {
            outfit.transformationData = data
        }

        if let collage = OutfitSanitizer.collageImage(for: outfit, canvasSize: canvasSize),
           let imageData = collage.processForStorage() {
            outfit.image = imageData
        }

        return outfit
    }

    // MARK: - Auto-grid (mirrors OutfitAddView.autoGridLayout)

    private struct LayoutSlot {
        let item: Item
        let position: CGPoint
        let scale: CGFloat
        let rotation: Double
        let zIndex: Int
    }

    private static func autoGridSlots(items: [Item], canvasSize: CGFloat) -> [LayoutSlot] {
        let count = items.count
        guard count > 0 else { return [] }

        let columns: Int
        let rows: Int
        switch count {
        case 1:
            columns = 1
            rows = 1
        case 2:
            columns = 2
            rows = 1
        case 3, 4:
            columns = 2
            rows = 2
        default:
            columns = Int(ceil(sqrt(Double(count))))
            rows = Int(ceil(Double(count) / Double(columns)))
        }

        let gap: CGFloat = 8
        let cellWidth = (canvasSize - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (canvasSize - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let padding: CGFloat = 0.88

        return items.enumerated().map { layoutIndex, item in
            let column = layoutIndex % columns
            let row = layoutIndex / columns
            let centerX = CGFloat(column) * (cellWidth + gap) + cellWidth / 2
            let centerY = CGFloat(row) * (cellHeight + gap) + cellHeight / 2

            let bounds = PhotoContentBounds.contentBounds(for: item)
            let displaySize = OutfitItem.defaultDisplaySize(
                canvasSize: canvasSize,
                contentAspect: bounds.aspectRatio
            )
            let fitScale = min(
                cellWidth * padding / max(displaySize.width, 1),
                cellHeight * padding / max(displaySize.height, 1)
            )

            return LayoutSlot(
                item: item,
                position: CGPoint(x: centerX, y: centerY),
                scale: max(0.3, min(4.0, fitScale)),
                rotation: 0,
                zIndex: layoutIndex
            )
        }
    }

    private static func deduplicatedActiveItems(_ items: [Item]) -> [Item] {
        var seen = Set<NSManagedObjectID>()
        var result: [Item] = []
        for item in items {
            guard item.isSoftDeleted != true, item.isDraft != true else { continue }
            guard seen.insert(item.objectID).inserted else { continue }
            result.append(item)
        }
        return result
    }
}
