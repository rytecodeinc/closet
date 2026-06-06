//
//  TagListView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct TagListView: View {
    private let content: AnyView

    init(item: Item) {
        content = AnyView(ItemTagListContent(item: item))
    }

    init(outfit: Outfit) {
        content = AnyView(OutfitTagListContent(outfit: outfit))
    }

    var body: some View {
        content
    }
}

private struct TagListHeader: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SelectionPanelHeader(
            title: "Select Tags",
            leading: {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Set Tags")
                    }
                    .foregroundColor(.blue)
                }
            },
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Item tags

private struct ItemTagListContent: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @State private var tags: [Tag] = []
    @State private var newTagName: String = ""

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: item.userId)
    }

    private var filteredTags: [Tag] {
        guard !newTagName.isEmpty else { return tags }
        let lowerInput = newTagName.lowercased()
        return tags.filter { ($0.name ?? "").lowercased().contains(lowerInput) }
    }

    /// Wishlist items use the full tag library (no wardrobe filter), matching brand picker behavior.
    private var wardrobeTypeForTagPicker: String? {
        let isWishlist = (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } == true
        return isWishlist ? nil : "closet"
    }

    var body: some View {
        VStack(spacing: 0) {
            TagListHeader()

            VStack(spacing: 12) {
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
                .padding(.top)

                if tags.isEmpty {
                    Text(wardrobeTypeForTagPicker == nil
                        ? "Tags used on your items will appear here."
                        : "Tags you add will appear in a list here.")
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                } else {
                    List {
                        ForEach(filteredTags, id: \.self) { tag in
                            Button {
                                toggleTag(tag)
                                dismiss()
                            } label: {
                                HStack {
                                    highlightedText(for: tag.name ?? "", matching: newTagName)
                                        .foregroundColor(.primary)
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
                    .listStyle(.plain)
                }
            }
        }
        .onAppear(perform: fetchTags)
        .toolbar(.hidden, for: .navigationBar)
    }

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

    private func fetchTags() {
        guard let uid = referenceUserId, !uid.isEmpty else {
            tags = []
            return
        }
        do {
            tags = try viewContext.fetchTagsForItemPicker(
                userId: uid,
                wardrobeType: wardrobeTypeForTagPicker,
                includingTagsOn: item
            )
        } catch {
            print("❌ Failed to fetch tags: \(error)")
            tags = []
        }
    }

    private func toggleTag(_ tag: Tag) {
        if let tags = item.tags as? Set<Tag>, tags.contains(tag) {
            item.removeFromTags(tag)
        } else {
            item.addToTags(tag)
        }

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
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = tags.first(where: { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            toggleTag(existing)
            newTagName = ""
            return
        }

        let newTag = Tag(context: viewContext)
        newTag.name = trimmed
        newTag.id = UUID()
        newTag.userId = referenceUserId ?? item.userId

        item.addToTags(newTag)

        if viewContext.parent == nil {
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save tag: \(error.localizedDescription)")
            }
        }

        newTagName = ""
        fetchTags()
        dismiss()
    }

    private func deleteTag(_ tag: Tag) {
        guard let tagId = tag.id else { return }

        let affectedItems: [Item] = (tag.items as? Set<Item>).map(Array.init) ?? []
        let affectedOutfits: [Outfit] = (tag.outfits as? Set<Outfit>).map(Array.init) ?? []

        for anItem in affectedItems {
            anItem.removeFromTags(tag)
            setUpdatedAt(anItem)
        }
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

// MARK: - Outfit tags

private struct OutfitTagListContent: View {
    @ObservedObject var outfit: Outfit
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @State private var tags: [Tag] = []
    @State private var newTagName: String = ""

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: outfit.userId)
    }

    private var filteredTags: [Tag] {
        guard !newTagName.isEmpty else { return tags }
        let lowerInput = newTagName.lowercased()
        return tags.filter { ($0.name ?? "").lowercased().contains(lowerInput) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TagListHeader()

            VStack(spacing: 12) {
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
                .padding(.top)

                if tags.isEmpty {
                    Text("Tags added to your outfits will appear here.")
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                } else {
                    List {
                        ForEach(filteredTags, id: \.self) { tag in
                            Button {
                                toggleTag(tag)
                                dismiss()
                            } label: {
                                HStack {
                                    highlightedText(for: tag.name ?? "", matching: newTagName)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if (outfit.tags as? Set<Tag>)?.contains(tag) == true {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .onAppear(perform: fetchTags)
        .toolbar(.hidden, for: .navigationBar)
    }

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

    private func fetchTags() {
        guard let uid = referenceUserId, !uid.isEmpty else {
            tags = []
            return
        }
        do {
            var fetched = try viewContext.fetchOutfitTagsForFilterList(userId: uid)
            if let outfitTags = outfit.tags as? Set<Tag> {
                for tag in outfitTags where !fetched.contains(where: { $0.objectID == tag.objectID }) {
                    fetched.append(tag)
                }
                fetched.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            }
            tags = fetched
        } catch {
            print("❌ Failed to fetch tags: \(error)")
            tags = []
        }
    }

    private func toggleTag(_ tag: Tag) {
        if let tags = outfit.tags as? Set<Tag>, tags.contains(tag) {
            outfit.removeFromTags(tag)
        } else {
            outfit.addToTags(tag)
        }

        do {
            try viewContext.save()
            if (outfit.tags as? Set<Tag>)?.contains(tag) == false {
                cleanupTagIfOrphaned(tag)
            }
        } catch {
            print("❌ Failed to save tag: \(error.localizedDescription)")
        }
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = tags.first(where: { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            toggleTag(existing)
            newTagName = ""
            return
        }

        let newTag = Tag(context: viewContext)
        newTag.name = trimmed
        newTag.id = UUID()
        newTag.userId = referenceUserId ?? outfit.userId

        outfit.addToTags(newTag)

        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to save tag: \(error.localizedDescription)")
        }

        newTagName = ""
        fetchTags()
        dismiss()
    }
}
