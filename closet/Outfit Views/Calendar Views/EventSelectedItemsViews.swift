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
    /// When true, mosaic fills its container edge-to-edge with no rounded inset.
    var fillsEdgeToEdge: Bool = false

    private let gap: CGFloat = 1

    init(thumbnails: [EventSelectedThumbnail], fillsEdgeToEdge: Bool = false) {
        self.thumbnails = thumbnails
        self.fillsEdgeToEdge = fillsEdgeToEdge
    }

    init(items: [Item], fillsEdgeToEdge: Bool = false) {
        self.thumbnails = items.map { .item($0) }
        self.fillsEdgeToEdge = fillsEdgeToEdge
    }

    var body: some View {
        Group {
            switch thumbnails.count {
            case 1:
                eventCell(for: thumbnails[0])
                    .aspectRatio(1, contentMode: fillsEdgeToEdge ? .fill : .fit)
            case 2:
                // Two equal squares sharing the row width (not a full-width square).
                HStack(spacing: gap) {
                    ForEach(thumbnails.prefix(2)) { thumbnail in
                        eventCell(for: thumbnail)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            case 3:
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        eventCell(for: thumbnails[0])
                        eventCell(for: thumbnails[1])
                    }
                    eventCell(for: thumbnails[2])
                }
                .aspectRatio(1, contentMode: .fit)
            case 4:
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        eventCell(for: thumbnails[0])
                        eventCell(for: thumbnails[1])
                    }
                    HStack(spacing: gap) {
                        eventCell(for: thumbnails[2])
                        eventCell(for: thumbnails[3])
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            default:
                let columns = Array(
                    repeating: GridItem(.flexible(), spacing: gap),
                    count: 3
                )
                LazyVGrid(columns: columns, spacing: gap) {
                    ForEach(thumbnails) { thumbnail in
                        eventCell(for: thumbnail)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .modifier(EventSelectedItemsClipModifier(fillsEdgeToEdge: fillsEdgeToEdge))
    }

    @ViewBuilder
    private func eventCell(for thumbnail: EventSelectedThumbnail) -> some View {
        Group {
            switch thumbnail {
            case .item(let item):
                EventItemThumbnailView(item: item, clipsRounded: !fillsEdgeToEdge)
            case .outfit(let outfit):
                EventOutfitThumbnailView(outfit: outfit, clipsRounded: !fillsEdgeToEdge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct EventSelectedItemsClipModifier: ViewModifier {
    let fillsEdgeToEdge: Bool

    func body(content: Content) -> some View {
        if fillsEdgeToEdge {
            content
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

struct EventItemThumbnailView: View {
    let item: Item
    var clipsRounded: Bool = true

    var body: some View {
        ZStack {
            Color(.systemBackground)
            if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
               let data = primaryPhoto.data,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else if let imageData = item.image,
                      let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                Color(.systemGray5)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .modifier(EventThumbnailRoundedClip(enabled: clipsRounded))
    }
}

struct EventOutfitThumbnailView: View {
    let outfit: Outfit
    var clipsRounded: Bool = true

    var body: some View {
        ZStack {
            // Opaque base so transparent collage pixels don’t show List/grouped gray behind.
            Color(.systemBackground)
            if let imageData = outfit.image,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                Color(.systemGray5)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .modifier(EventThumbnailRoundedClip(enabled: clipsRounded))
    }
}

private struct EventThumbnailRoundedClip: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            content
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

    private var selectionSummary: String {
        switch (items.count, outfits.count) {
        case (0, 0):
            return isReadOnly ? "No items or outfits" : "Add items or outfits"
        case let (itemCount, 0) where itemCount > 0:
            return "\(itemCount) item\(itemCount == 1 ? "" : "s") selected"
        case let (0, outfitCount) where outfitCount > 0:
            return "\(outfitCount) outfit\(outfitCount == 1 ? "" : "s") selected"
        default:
            return "\(items.count) item\(items.count == 1 ? "" : "s"), \(outfits.count) outfit\(outfits.count == 1 ? "" : "s")"
        }
    }

    var body: some View {
        Group {
            if isReadOnly {
                sectionContent(showsChevron: false)
            } else {
                Button(action: onTap) {
                    sectionContent(showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionContent(showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "tshirt")
                    .foregroundColor(.gray)
                    .frame(width: 22)

                Text(selectionSummary)
                    .foregroundColor(items.count + outfits.count > 0 ? .primary : .secondary)

                Spacer(minLength: 0)
            }

            if !thumbnails.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Color.clear
                        .frame(width: 22)

                    EventSelectedItemsDisplayArea(thumbnails: thumbnails)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.trailing, showsChevron ? 12 : 0)
        .overlay(alignment: .trailing) {
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
