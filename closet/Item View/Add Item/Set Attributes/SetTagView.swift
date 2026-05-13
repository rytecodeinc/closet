//
//  TagSelectionView.swift
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

    @State private var tags: [Tag] = []
    @State private var showAddTagView: Bool = false

    var selectedTags: [Tag] {
        (item.tags as? Set<Tag>)?.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) ?? []
    }

    var body: some View {
        SelectionHeader(title: "Select Tags")

        VStack(alignment: .leading, spacing: 12) {
            // Add Tag Button
            Button(action: {
                showAddTagView = true
            }) {
                Label("Add Tag", systemImage: "plus")
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
            }

            // Tag Cloud
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
        .onAppear {
            fetchTags()
        }
        .sheet(isPresented: $showAddTagView) {
            SetTagDisplayView(item: item)
                .environment(\.managedObjectContext, viewContext)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Fetch Tags
    private func fetchTags() {
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        if let uid = item.userId, !uid.isEmpty {
            request.predicate = NSPredicate(format: "userId == %@", uid)
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
