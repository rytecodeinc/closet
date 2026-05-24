//
//  SetOutfitTagDisplayView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import CoreData

struct SetOutfitTagDisplayView: View {
    @ObservedObject var outfit: Outfit
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @State private var tags: [Tag] = []
    @State private var newTagName: String = ""

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: outfit.userId)
    }

    private var wardrobeTypeForTags: String {
        guard let items = outfit.items as? Set<Item> else { return "closet" }
        return items.contains { item in
            (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } == true
        } ? "wishlist" : "closet"
    }

    private var filteredTags: [Tag] {
        guard !newTagName.isEmpty else { return tags }
        let lowerInput = newTagName.lowercased()
        return tags.filter { ($0.name ?? "").lowercased().contains(lowerInput) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "Select Tag")
            
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
                                    if (outfit.tags as? Set<Tag>)?.contains(tag) == true {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
        }
        .onAppear {
            fetchTags()
        }
        .presentationDetents([.medium, .large])
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
            var fetched = try viewContext.fetchTagsForItemPicker(
                userId: uid,
                wardrobeType: wardrobeTypeForTags
            )
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
