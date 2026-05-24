//
//  SetOutfitTagView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import CoreData

struct SetOutfitTagView: View {
    @ObservedObject var outfit: Outfit
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @State private var tags: [Tag] = []
    @State private var showAddTagView: Bool = false

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: outfit.userId)
    }

    var selectedTags: [Tag] {
        (outfit.tags as? Set<Tag>)?.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) ?? []
    }

    private var wardrobeTypeForTags: String {
        guard let items = outfit.items as? Set<Item> else { return "closet" }
        return items.contains { item in
            (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } == true
        } ? "wishlist" : "closet"
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "Select Tags")
            
            VStack(alignment: .leading, spacing: 12) {
                Button(action: {
                    showAddTagView = true
                }) {
                    Label("Add Tag", systemImage: "plus")
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal)
                        .padding(.top)
                }

                if selectedTags.isEmpty {
                    Text("No tags have been added.")
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                } else {
                    TagCloudView(tags: selectedTags) { tagToRemove in
                        toggleTag(tagToRemove)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
        .onAppear {
            fetchTags()
        }
        .sheet(isPresented: $showAddTagView) {
            SetOutfitTagDisplayView(outfit: outfit)
                .environment(\.managedObjectContext, viewContext)
        }
        .presentationDetents([.medium, .large])
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
}
