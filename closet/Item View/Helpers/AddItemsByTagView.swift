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
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var tags: [Tag] = []
    @State private var selectedTag: Tag?
    @State private var isAddingItems = false
    
    var body: some View {
        NavigationView {
            List {
                if tags.isEmpty {
                    Text("No tags available. Add tags to items first.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            selectedTag = tag
                            addItemsByTag(tag)
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
            .navigationTitle("Add by Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchTags()
            }
        }
    }
    
    private func fetchTags() {
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        do {
            tags = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch tags: \(error.localizedDescription)")
            tags = []
        }
    }
    
    private func addItemsByTag(_ tag: Tag) {
        guard let tagName = tag.name else { return }
        
        isAddingItems = true
        
        // Fetch all items that have this tag
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.predicate = NSPredicate(format: "ANY tags.name == %@ AND isDraft != YES", tagName)
        
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
            
            print("✅ Added \(itemsToAdd.count) items with tag '\(tagName)' to wardrobe '\(wardrobe.name ?? "unknown")'")
            
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

