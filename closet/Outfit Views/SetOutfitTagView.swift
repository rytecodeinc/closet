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
    @State private var navigateToTagList = false

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: outfit.userId)
    }

    var selectedTags: [Tag] {
        (outfit.tags as? Set<Tag>)?.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) ?? []
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
                                "Remove \"\(tag.name ?? "this tag")\" from this outfit?"
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
                TagListView(outfit: outfit)
            }
        }
        .onAppear {
            fetchTags()
        }
        .presentationDetents([.medium, .large])
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
}
