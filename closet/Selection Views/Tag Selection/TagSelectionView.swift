//
//  TagSelectionView.swift
//  closet
//
//  Created by Dan Warner on 7/29/25.
//


import SwiftUI
import CoreData

struct TagSelectionView: View {
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
            TagDisplayView(item: item)
                
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Fetch Tags
    private func fetchTags() {
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
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
        saveContext()
    }

    // MARK: - Save Context
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to save context: \(error)")
        }
    }
}



