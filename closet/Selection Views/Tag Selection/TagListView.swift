//
//  BrandListView.swift
//  closet
//
//  Created by Dan Warner on 7/31/25.
//


import SwiftUI
import CoreData
import Foundation

struct TagListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedTags: Set<Tag>

    @State private var tags: [Tag] = []

    var body: some View {
        List {
            if tags.isEmpty {
                Text("Tags added to your closet will appear here.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(tags, id: \.self) { tag in
                    let name = tag.name ?? ""
                    Button {
                        toggleTagSelection(tag)
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedTags.contains(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Tags")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fetchTags)
    }

    private func toggleTagSelection(_ tag: Tag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func fetchTags() {
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
     //   request.predicate = NSPredicate(format: "isVisible == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        do {
            tags = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch tags: \(error.localizedDescription)")
            tags = []
        }
    }
}

