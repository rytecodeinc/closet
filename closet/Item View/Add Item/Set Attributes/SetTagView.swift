//
//  SetTagView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetTagView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @State private var tags: [Tag] = []
    @State private var navigateToTagList = false

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: item.userId)
    }

    /// Wishlist items use the full tag library (no wardrobe filter), matching brand picker behavior.
    private var wardrobeTypeForTagPicker: String? {
        let isWishlist = (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } == true
        return isWishlist ? nil : "closet"
    }

    var selectedTags: [Tag] {
        (item.tags as? Set<Tag>)?.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SelectionPanelHeader(
                    title: "Set Tags",
                    leading: { EmptyView() },
                    trailing: {
                        Button {
                            navigateToTagList = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .foregroundColor(.blue)
                    }
                )

                if selectedTags.isEmpty {
                    Text("No tags have been added.")
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView(showsIndicators: false) {
                        TagCloudView(
                            tags: selectedTags,
                            removeConfirmationMessage: { tag in
                                "Remove \"\(tag.name ?? "this tag")\" from this item?"
                            },
                            onRemove: { tagToRemove in
                                toggleTag(tagToRemove)
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $navigateToTagList) {
                TagListView(item: item)
            }
        }
        .onAppear {
            fetchTags()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Fetch Tags
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

    // MARK: - Toggle Tag Selection
    private func toggleTag(_ tag: Tag) {
        if let tags = item.tags as? Set<Tag>, tags.contains(tag) {
            item.removeFromTags(tag)
        } else {
            item.addToTags(tag)
        }
        
        // Set updatedAt since we're modifying the item
        setUpdatedAt(item)
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        if viewContext.parent == nil {
            do {
                try viewContext.save()
                if (item.tags as? Set<Tag>)?.contains(tag) == false {
                    cleanupTagIfOrphaned(tag)
                }
                SyncService.shared.syncItemIfNeeded(item)
            } catch {
                print("❌ Failed to save tag: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
    }
}
