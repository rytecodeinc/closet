//
//  SetOutfitCategoryView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import CoreData

struct SetOutfitCategoryView: View {
    @ObservedObject var outfit: Outfit
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [String] = []
    @State private var newCategoryName: String = ""
    
    var filteredCategories: [String] {
        guard !newCategoryName.isEmpty else { return categories }
        let lowercaseInput = newCategoryName.lowercased()
        return categories.filter { $0.lowercased().contains(lowercaseInput) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "Select Category")
            
            VStack(spacing: 12) {
                HStack {
                    TextField("Add or select a category", text: $newCategoryName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Add") {
                        addCategory()
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)
                .padding(.top)
                
                if categories.isEmpty {
                    Text("No categories have been added.")
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                } else {
                    List {
                        ForEach(filteredCategories, id: \.self) { category in
                            Button(action: {
                                // Toggle selection
                                if outfit.category == category {
                                    outfit.category = nil
                                } else {
                                    outfit.category = category
                                }
                                
                                do {
                                    try viewContext.save()
                                } catch {
                                    print("❌ Failed to save category: \(error.localizedDescription)")
                                }
                                
                                dismiss()
                            }) {
                                HStack {
                                    highlightedText(for: category, matching: newCategoryName)
                                        .foregroundColor(.black)
                                    Spacer()
                                    if outfit.category == category {
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
        }
        .onAppear {
            fetchCategories()
        }
    }

    // MARK: - Highlight Matching Text
    private func highlightedText(for categoryName: String, matching input: String) -> Text {
        let lowerCategory = categoryName.lowercased()
        let lowerInput = input.lowercased()
        
        guard let range = lowerCategory.range(of: lowerInput) else {
            return Text(categoryName)
        }

        let nsRange = NSRange(range, in: categoryName)
        let start = categoryName.startIndex
        let matchStart = categoryName.index(start, offsetBy: nsRange.location)
        let matchEnd = categoryName.index(matchStart, offsetBy: nsRange.length)

        let before = String(categoryName[..<matchStart])
        let match = String(categoryName[matchStart..<matchEnd])
        let after = String(categoryName[matchEnd...])

        return Text(before) + Text(match).bold() + Text(after)
    }

    // MARK: - Fetch Categories
    private func fetchCategories() {
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.propertiesToFetch = ["category"]
        
        do {
            let allOutfits = try viewContext.fetch(request)
            // Get unique, non-empty categories
            let allCategories = allOutfits.compactMap { $0.category }.filter { !$0.isEmpty }
            categories = Array(Set(allCategories)).sorted()
        } catch {
            print("❌ Failed to fetch categories: \(error)")
            categories = []
        }
    }

    // MARK: - Add Category
    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let categoryExists = categories.contains { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        
        if categoryExists {
            // Category exists - just assign it
            if let existing = categories.first(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                outfit.category = existing
                
                do {
                    try viewContext.save()
                } catch {
                    print("❌ Failed to save category: \(error.localizedDescription)")
                }
                
                dismiss()
            }
            return
        }

        // Set new category
        outfit.category = trimmed
        
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to save category: \(error.localizedDescription)")
        }
        
        newCategoryName = ""
        fetchCategories()
        dismiss()
    }
}

