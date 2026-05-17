//
//  TagDisplayView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetTagDisplayView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var tags: [Tag] = []
    @State private var newTagName: String = ""

    private var filteredTags: [Tag] {
        guard !newTagName.isEmpty else { return tags }
        let lowerInput = newTagName.lowercased()
        return tags.filter { ($0.name ?? "").lowercased().contains(lowerInput) }
    }

    var body: some View {
        SelectionHeader(title: "Select Tag")

        VStack(spacing: 12) {
            // Search / Add row
            HStack {
                TextField("Add or select a tag", text: $newTagName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.words)

                Button("Add") {
                    addTag()
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)

            // Tag List
            if tags.isEmpty {
                Text(wardrobeTypeForTags == "wishlist"
                    ? "Tags used on wishlist items will appear here."
                    : "Tags you add will appear in a list here.")
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                List {
                    ForEach(filteredTags, id: \.self) { tag in
                        Button(action: {
                            toggleTag(tag)
                            dismiss()
                        }) {
                            HStack {
                                highlightedText(for: tag.name ?? "", matching: newTagName)
                                    .foregroundColor(.black)
                                Spacer()
                                if (item.tags as? Set<Tag>)?.contains(tag) == true {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if viewContext.parent == nil {
                                Button(role: .destructive) {
                                    deleteTag(tag)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .onAppear {
            fetchTags()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Highlight Matching Text
    private func highlightedText(for tagName: String, matching input: String) -> Text {
        let lowerTag = tagName.lowercased()
        let lowerInput = input.lowercased()

        guard let range = lowerTag.range(of: lowerInput) else {
            return Text(tagName)
        }

        let nsRange = NSRange(range, in: tagName)
        let start = tagName.startIndex
        let matchStart = tagName.index(start, offsetBy: nsRange.location)
        let matchEnd = tagName.index(matchStart, offsetBy: nsRange.length)

        let before = String(tagName[..<matchStart])
        let match = String(tagName[matchStart..<matchEnd])
        let after = String(tagName[matchEnd...])

        return Text(before) + Text(match).bold() + Text(after)
    }

    /// Derive wardrobe context from item: if item is in any wishlist wardrobe, use wishlist tags; else closet tags.
    private var wardrobeTypeForTags: String {
        (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } == true ? "wishlist" : "closet"
    }

    // MARK: - Fetch Tags
    private func fetchTags() {
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        if let uid = item.userId, !uid.isEmpty {
            let owned = NSPredicate(format: "userId == %@", uid)
            let fromWardrobe = NSPredicate(
                format: "SUBQUERY(items, $i, ANY $i.wardrobes.type == %@ AND $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                wardrobeTypeForTags,
                uid
            )
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, fromWardrobe])
        } else {
            request.predicate = NSPredicate(format: "SUBQUERY(items, $i, ANY $i.wardrobes.type == %@).@count > 0", wardrobeTypeForTags)
        }
        do {
            tags = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch tags: \(error)")
            tags = []
        }
    }

    // MARK: - Toggle Tag Selection
    private func toggleTag(_ tag: Tag) {
        if let tags = item.tags as? Set<Tag>, tags.contains(tag) {
            item.removeFromTags(tag)
        } else {
            item.addToTags(tag)
        }
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        if viewContext.parent == nil {
            do {
                try viewContext.save()
                if (item.tags as? Set<Tag>)?.contains(tag) == false {
                    cleanupTagIfOrphaned(tag)
                }
            } catch {
                print("❌ Failed to save tag: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
    }

    // MARK: - Add New Tag
    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = tags.first(where: { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            toggleTag(existing)
            newTagName = ""
            return
        }

        // Create new tag in the same context (child context)
        let newTag = Tag(context: viewContext)
        newTag.name = trimmed
        newTag.id = UUID()
        newTag.userId = item.userId

        item.addToTags(newTag)
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        if viewContext.parent == nil {
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save tag: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it

        newTagName = ""
        fetchTags()
        dismiss()
    }

    // MARK: - Delete Tag
    /// Removes tag from all items and outfits, deletes from Core Data, and Supabase.
    private func deleteTag(_ tag: Tag) {
        guard let tagId = tag.id else { return }

        // Collect affected items and outfits before modifying (relationships clear after delete)
        let affectedItems: [Item] = (tag.items as? Set<Item>).map(Array.init) ?? []
        let affectedOutfits: [Outfit] = (tag.outfits as? Set<Outfit>).map(Array.init) ?? []

        // Remove tag from all items
        for anItem in affectedItems {
            anItem.removeFromTags(tag)
            setUpdatedAt(anItem)
        }
        // Remove tag from all outfits
        for outfit in affectedOutfits {
            outfit.removeFromTags(tag)
            setUpdatedAt(outfit)
        }

        viewContext.delete(tag)

        if viewContext.parent == nil {
            do {
                try viewContext.save()
                SyncService.shared.deleteTagFromSupabase(tagId: tagId)
                for anItem in affectedItems {
                    SyncService.shared.syncItemIfNeeded(anItem)
                }
                for outfit in affectedOutfits {
                    SyncService.shared.syncOutfitIfNeeded(outfit)
                }
            } catch {
                print("❌ Failed to delete tag: \(error.localizedDescription)")
                return
            }
        }

        fetchTags()
    }
}
