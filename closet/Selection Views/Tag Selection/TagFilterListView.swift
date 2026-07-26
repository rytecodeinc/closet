//
//  TagFilterListView.swift
//  closet
//
//  Created by Dan Warner on 7/31/25.
//

import SwiftUI
import CoreData
import Foundation

enum TagListSource: String {
    /// Tags used on items (optionally wardrobe-type / wardrobe scoped).
    case items
    /// Tags attached directly to outfits.
    case outfits
    /// Tags used on items or outfits.
    case itemsAndOutfits
}

struct TagFilterListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedTags: Set<Tag>
    /// When true, filter for entities with no tags. Mutually exclusive with `selectedTags`.
    @Binding var filterNotSet: Bool
    var source: TagListSource = .items
    /// When "wishlist", only tags from wishlist items. When "closet", only from closet items. When nil (e.g. outfit filter), all tags.
    var wardrobeType: String? = "closet"
    /// When set, tags are limited to those used by this user's items/outfits.
    var userId: String? = nil
    /// When non-empty, only tags on items in all of these wardrobes (AND) appear.
    var wardrobes: [Wardrobe] = []
    /// When set with `source == .outfits`, only tags on outfits visible in this wardrobe tab appear.
    var outfitFilterWardrobe: Wardrobe? = nil

    @State private var tags: [Tag] = []

    private var emptyStateLabel: String {
        let tagSource: String
        switch source {
        case .items:
            let kind = (wardrobeType ?? "items").lowercased()
            if kind == "wishlist" { tagSource = "wishlist items" }
            else if kind == "closet" { tagSource = "closet items" }
            else { tagSource = "items" }
        case .outfits:
            if outfitFilterWardrobe?.type?.lowercased() == "wishlist" {
                tagSource = "outfits in this wishlist"
            } else if outfitFilterWardrobe?.type?.lowercased() == "closet" {
                tagSource = "outfits in this closet"
            } else {
                tagSource = "outfits"
            }
        case .itemsAndOutfits:
            tagSource = "items and outfits"
        }
        return "Tags added to \(tagSource) will appear here."
    }

    var body: some View {
        List {
            tagsNotSetRow

            if tags.isEmpty {
                Text(emptyStateLabel)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(tags, id: \.self) { tag in
                    let name = tag.name ?? ""
                    Button {
                        toggleTagSelection(tag)
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundColor(.primary)
                            Spacer()
                            if !filterNotSet, selectedTags.contains(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Tags")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fetchTags)
    }

    private var tagsNotSetRow: some View {
        HStack {
            Text("None")
                .foregroundColor(.black)

            Spacer()

            if filterNotSet {
                Image(systemName: "checkmark").foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTags.removeAll()
            filterNotSet = true
        }
    }

    private func toggleTagSelection(_ tag: Tag) {
        filterNotSet = false
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func fetchTags() {
        do {
            switch source {
            case .outfits:
                tags = try viewContext.fetchOutfitTagsForFilterList(
                    userId: userId,
                    wardrobe: outfitFilterWardrobe
                )
            case .items:
                tags = try viewContext.fetchTagsForFilterList(
                    userId: userId,
                    wardrobeType: wardrobeType,
                    wardrobes: wardrobes
                )
            case .itemsAndOutfits:
                tags = try viewContext.fetchTagsForFilterList(
                    userId: userId,
                    wardrobeType: nil,
                    wardrobes: []
                )
            }
        } catch {
            print("❌ Failed to fetch tags: \(error.localizedDescription)")
            tags = []
        }
    }
}
