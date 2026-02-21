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

    @State private var tags: [Tag] = []
    @State private var showAddTagView: Bool = false

    var selectedTags: [Tag] {
        (outfit.tags as? Set<Tag>)?.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
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
                        .padding(.top)
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
        }
        .onAppear {
            fetchTags()
        }
        .sheet(isPresented: $showAddTagView) {
            NavigationView {
                SetOutfitTagDisplayView(outfit: outfit)
                    .environment(\.managedObjectContext, viewContext)
            }
            .presentationDetents([.medium, .large])
        }
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
        if let tags = outfit.tags as? Set<Tag>, tags.contains(tag) {
            outfit.removeFromTags(tag)
        } else {
            outfit.addToTags(tag)
        }
        
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to save tag: \(error.localizedDescription)")
        }
    }
}

