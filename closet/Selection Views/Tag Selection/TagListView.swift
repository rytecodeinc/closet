//
//  BrandListView.swift
//  closet
//
//  Created by Dan Warner on 7/31/25.
//


import SwiftUI
import CoreData
import Foundation

struct TagListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedTags: Set<Tag>
    /// When "wishlist", only tags from wishlist items. When "closet", only from closet items. When nil (e.g. outfit filter), all tags.
    var wardrobeType: String? = "closet"
    /// When set, tags are limited to those used by this user's items/outfits.
    var userId: String? = nil

    @State private var tags: [Tag] = []

    var body: some View {
        List {
            if tags.isEmpty {
                Text(wardrobeType == "wishlist"
                    ? "Tags used on wishlist items will appear here."
                    : wardrobeType == "closet"
                    ? "Tags added to your closet will appear here."
                    : "Tags will appear here.")
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
                            if selectedTags.contains(tag) {
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

    private func toggleTagSelection(_ tag: Tag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func fetchTags() {
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]

        guard let uid = userId else {
            if let type = wardrobeType {
                request.predicate = NSPredicate(format: "SUBQUERY(items, $i, ANY $i.wardrobes.type == %@).@count > 0", type)
            }
            do {
                tags = try viewContext.fetch(request)
            } catch {
                print("❌ Failed to fetch tags: \(error.localizedDescription)")
                tags = []
            }
            return
        }

        let owned = NSPredicate(format: "userId == %@", uid)

        if let type = wardrobeType {
            let fromWardrobe = NSPredicate(
                format: "SUBQUERY(items, $i, ANY $i.wardrobes.type == %@ AND $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                type,
                uid
            )
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, fromWardrobe])
        } else {
            let fromItems = NSPredicate(
                format: "SUBQUERY(items, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                uid
            )
            let fromOutfits = NSPredicate(
                format: "SUBQUERY(outfits, $o, $o.userId == %@ AND ($o.isSoftDeleted != YES OR $o.isSoftDeleted == nil)).@count > 0",
                uid
            )
            let used = NSCompoundPredicate(orPredicateWithSubpredicates: [fromItems, fromOutfits])
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, used])
        }

        do {
            tags = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch tags: \(error.localizedDescription)")
            tags = []
        }
    }
}

