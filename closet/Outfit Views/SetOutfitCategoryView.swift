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
    @EnvironmentObject private var authSession: AuthSession

    @State private var categories: [OutfitCategory] = []
    @State private var newCategoryName: String = ""

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: outfit.userId)
    }
    
    var filteredCategories: [OutfitCategory] {
        guard !newCategoryName.isEmpty else { return categories }
        let lowercaseInput = newCategoryName.lowercased()
        return categories.filter { ($0.name ?? "").lowercased().contains(lowercaseInput) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: "Select Category")
            
            VStack(spacing: 12) {
                HStack {
                    TextField("Add or select a category", text: $newCategoryName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.words)

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
                        ForEach(filteredCategories, id: \.objectID) { category in
                            Button(action: {
                                toggleCategory(category)
                                dismiss()
                            }) {
                                HStack {
                                    highlightedText(for: category.name ?? "", matching: newCategoryName)
                                        .foregroundColor(.black)
                                    Spacer()
                                    if outfit.category?.objectID == category.objectID {
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
        .presentationDetents([.medium, .large])
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
        guard let uid = referenceUserId, !uid.isEmpty else {
            categories = []
            return
        }
        do {
            var fetched = try viewContext.fetchOutfitCategoriesForAttributePicker(userId: uid)
            if let current = outfit.category,
               !fetched.contains(where: { $0.objectID == current.objectID }) {
                fetched.append(current)
                fetched.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            }
            categories = fetched
        } catch {
            print("❌ Failed to fetch categories: \(error)")
            categories = []
        }
    }

    // MARK: - Toggle / Add Category
    private func toggleCategory(_ category: OutfitCategory) {
        if outfit.category?.objectID == category.objectID {
            let previous = outfit.category
            outfit.category = nil
            do {
                try viewContext.save()
                if let previous {
                    cleanupOutfitCategoryIfOrphaned(previous)
                }
            } catch {
                print("❌ Failed to save category: \(error.localizedDescription)")
            }
        } else {
            outfit.category = category
            setUpdatedAt(outfit)
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save category: \(error.localizedDescription)")
            }
        }
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let uid = referenceUserId else { return }

        if let existing = categories.first(where: { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            toggleCategory(existing)
            newCategoryName = ""
            return
        }

        do {
            let category = try viewContext.fetchOrCreateOutfitCategory(named: trimmed, userId: uid)
            outfit.category = category
            setUpdatedAt(outfit)
            try viewContext.save()
            newCategoryName = ""
            fetchCategories()
            dismiss()
        } catch {
            print("❌ Failed to save category: \(error.localizedDescription)")
        }
    }
}
