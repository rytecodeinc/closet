//
//  AddItemsByTagView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import CoreData

struct AddItemsByTagView: View {
    @ObservedObject var wardrobe: Wardrobe
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var tags: [Tag] = []
    @State private var selectedTag: Tag?
    @State private var isAddingItems = false
    @State private var tagPendingAdd: Tag?
    @State private var showAddConfirmation = false
    
    private var wardrobeDisplayName: String {
        wardrobe.name ?? "this wardrobe"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: "Add by Tag")

            List {
                if tags.isEmpty {
                    Text("No tags available. Add tags to items first.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            tagPendingAdd = tag
                            showAddConfirmation = true
                        } label: {
                            HStack {
                                Text(tag.name ?? "")
                                    .foregroundColor(.primary)
                                Spacer()
                                if isAddingItems && selectedTag == tag {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isAddingItems)
                    }
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            fetchTags()
        }
        .alert("Add Items by Tag", isPresented: $showAddConfirmation) {
            Button("Cancel", role: .cancel) {
                tagPendingAdd = nil
            }
            Button("Add") {
                if let tag = tagPendingAdd {
                    selectedTag = tag
                    addItemsByTag(tag)
                }
                tagPendingAdd = nil
            }
        } message: {
            if let tag = tagPendingAdd {
                Text("Add all items tagged \"\(tag.name ?? "")\" to \"\(wardrobeDisplayName)\"?")
            }
        }
    }
    
    private var currentUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: wardrobe.userId)
    }

    private func fetchTags() {
        guard let uid = currentUserId else {
            tags = []
            return
        }

        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]

        let owned = NSPredicate(format: "userId == %@", uid)
        let wardrobeType = wardrobe.type ?? "closet"
        let fromWardrobe = NSPredicate(
            format: "SUBQUERY(items, $i, ANY $i.wardrobes.type == %@ AND $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
            wardrobeType,
            uid
        )
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, fromWardrobe])

        do {
            let fetched = try viewContext.fetch(request)
            tags = dedupeNamedReferenceRows(fetched, preferredUserId: uid)
        } catch {
            print("❌ Failed to fetch tags: \(error.localizedDescription)")
            tags = []
        }
    }
    
    private func addItemsByTag(_ tag: Tag) {
        guard let uid = currentUserId else { return }
        
        isAddingItems = true
        
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.predicate = NSPredicate(
            format: "ANY tags == %@ AND userId == %@ AND isDraft != YES AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            tag,
            uid
        )
        
        do {
            let allItemsWithTag = try viewContext.fetch(request)
            
            // Get items already in this wardrobe
            let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
            
            // Filter to only items not already in this wardrobe
            let itemsToAdd = allItemsWithTag.filter { !itemsInWardrobe.contains($0) }
            
            // Add all items to the wardrobe
            for item in itemsToAdd {
                wardrobe.addToItems(item)
            }
            
            try viewContext.save()
            
            print("✅ Added \(itemsToAdd.count) items with tag '\(tag.name ?? "")' to wardrobe '\(wardrobe.name ?? "unknown")'")
            
            // Dismiss after a short delay to show success
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } catch {
            print("❌ Failed to add items by tag: \(error.localizedDescription)")
            isAddingItems = false
        }
    }
}

