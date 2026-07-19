//
//  EventSelectedItemsViews.swift
//  closet
//

import SwiftUI
import UIKit
import CoreData

/// Unified thumbnail entry so selected outfits and items share one mosaic with equal cell sizes.
enum EventSelectedThumbnail: Identifiable {
    case item(Item)
    case outfit(Outfit)

    var id: NSManagedObjectID {
        switch self {
        case .item(let item): return item.objectID
        case .outfit(let outfit): return outfit.objectID
        }
    }
}

struct EventSelectedItemsDisplayArea: View {
    let thumbnails: [EventSelectedThumbnail]

    init(thumbnails: [EventSelectedThumbnail]) {
        self.thumbnails = thumbnails
    }

    init(items: [Item]) {
        self.thumbnails = items.map { .item($0) }
    }

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            let gap: CGFloat = 1

            switch thumbnails.count {
            case 1:
                eventCell(for: thumbnails[0], width: side, height: side)
            case 2:
                let half = (side - gap) / 2
                HStack(spacing: gap) {
                    ForEach(thumbnails.prefix(2)) { thumbnail in
                        eventCell(for: thumbnail, width: half, height: side)
                    }
                }
            case 3:
                let half = (side - gap) / 2
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        eventCell(for: thumbnails[0], width: half, height: half)
                        eventCell(for: thumbnails[1], width: half, height: half)
                    }
                    eventCell(for: thumbnails[2], width: side, height: half)
                }
            case 4:
                let cellSide = (side - gap) / 2
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        eventCell(for: thumbnails[0], width: cellSide, height: cellSide)
                        eventCell(for: thumbnails[1], width: cellSide, height: cellSide)
                    }
                    HStack(spacing: gap) {
                        eventCell(for: thumbnails[2], width: cellSide, height: cellSide)
                        eventCell(for: thumbnails[3], width: cellSide, height: cellSide)
                    }
                }
            default:
                eventMosaicGrid(side: side, gap: gap)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func eventMosaicGrid(side: CGFloat, gap: CGFloat) -> some View {
        let columnsCount = 3
        let rows = Int(ceil(Double(thumbnails.count) / Double(columnsCount)))
        let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: columnsCount)
        let cellWidth = (side - gap * CGFloat(columnsCount - 1)) / CGFloat(columnsCount)
        let cellHeight = (side - gap * CGFloat(rows - 1)) / CGFloat(rows)

        return LazyVGrid(columns: columns, spacing: gap) {
            ForEach(thumbnails) { thumbnail in
                eventCell(for: thumbnail, width: cellWidth, height: cellHeight)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }

    @ViewBuilder
    private func eventCell(for thumbnail: EventSelectedThumbnail, width: CGFloat, height: CGFloat) -> some View {
        Group {
            switch thumbnail {
            case .item(let item):
                EventItemThumbnailView(item: item)
            case .outfit(let outfit):
                EventOutfitThumbnailView(outfit: outfit)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

struct EventItemThumbnailView: View {
    let item: Item

    var body: some View {
        if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
           let data = primaryPhoto.data,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let imageData = item.image,
                  let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                        .font(.caption)
                )
        }
    }
}

struct EventOutfitThumbnailView: View {
    let outfit: Outfit

    var body: some View {
        if let imageData = outfit.image,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                        .font(.caption)
                )
        }
    }
}

struct EventItemsSelectionRow: View {
    let selectedItemsCount: Int
    let selectedOutfitsCount: Int
    /// Read-only rows (event detail) show no chevron and ignore taps.
    var isReadOnly: Bool = false
    let onTap: () -> Void

    private var selectionSummary: String {
        switch (selectedItemsCount, selectedOutfitsCount) {
        case (0, 0):
            return isReadOnly ? "No items or outfits" : "Add items or outfits"
        case let (items, 0) where items > 0:
            return "\(items) item\(items == 1 ? "" : "s") selected"
        case let (0, outfits) where outfits > 0:
            return "\(outfits) outfit\(outfits == 1 ? "" : "s") selected"
        default:
            return "\(selectedItemsCount) item\(selectedItemsCount == 1 ? "" : "s"), \(selectedOutfitsCount) outfit\(selectedOutfitsCount == 1 ? "" : "s")"
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "tshirt")
                .foregroundColor(.gray)
                .frame(width: 22)

            Text(selectionSummary)
                .foregroundColor(selectedItemsCount + selectedOutfitsCount > 0 ? .primary : .secondary)

            Spacer()

            if !isReadOnly {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    var body: some View {
        if isReadOnly {
            rowContent
        } else {
            Button(action: onTap) {
                rowContent
            }
            .buttonStyle(.plain)
        }
    }
}

struct EventItemsSelectionSection: View {
    let items: [Item]
    var outfits: [Outfit] = []
    var isReadOnly: Bool = false
    let onTap: () -> Void

    private var thumbnails: [EventSelectedThumbnail] {
        outfits.map { .outfit($0) } + items.map { .item($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EventItemsSelectionRow(
                selectedItemsCount: items.count,
                selectedOutfitsCount: outfits.count,
                isReadOnly: isReadOnly,
                onTap: onTap
            )

            if !thumbnails.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Color.clear
                        .frame(width: 22)

                    EventSelectedItemsDisplayArea(thumbnails: thumbnails)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
