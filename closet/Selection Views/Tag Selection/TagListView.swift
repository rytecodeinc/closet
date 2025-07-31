//
//  TagListView.swift
//  closet
//
//  Created by Dan Warner on 7/30/25.
//

import SwiftUI
import CoreData
import Foundation

struct TagListView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var tags: [Tag] = []
    @State private var newTagName: String = ""

    private var filteredTags: [Tag] {
        guard !newTagName.isEmpty else { return tags }
        let lowerInput = newTagName.lowercased()
        return tags.filter { ($0.name ?? "").lowercased().contains(lowerInput) }
    }

    var body: some View {
        SelectionHeader(title: "Select a Tag")

        VStack(spacing: 12) {
            // Search / Add row
            HStack {
                TextField("Add or select a tag", text: $newTagName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Add") {
                    addTag()
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)

            // Tag List
            if tags.isEmpty {
                Text("No tags have been added.")
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
                                if (item.tags as? Set<Tag>)?.contains(tag) == true {
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
        .onAppear {
            fetchTags()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Highlight Matching Text
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

    // MARK: - Add New Tag
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

        item.addToTags(newTag)
        saveContext()

        newTagName = ""
        fetchTags()
        dismiss()
    }
}

