//
//  CategorySelectionView.swift
//  closet
//
//  Created by Dan Warner on 8/2/25.
//

import SwiftUI
import CoreData
import Foundation

struct CategorySelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategoryName: String?
    @State private var categories: [Category] = []

    var body: some View {
        VStack {
            SelectionHeader(title: "Select a Category")

            if categories.isEmpty {
                Text("No categories have been added.")
                    .foregroundColor(.gray)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(categories, id: \.self) { category in
                        let name = category.name ?? ""
                        HStack {
                            Text(name)
                                .foregroundColor(.black)
                            Spacer()
                            if selectedCategoryName == name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedCategoryName == name {
                                selectedCategoryName = nil
                            } else {
                                selectedCategoryName = name
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            fetchCategories()
            selectedCategoryName = item.category?.name
        }
        .onDisappear {
            guard let name = selectedCategoryName else {
                item.category = nil
                return
            }

            let category = fetchOrCreateCategory(named: name)
            item.category = category

            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save selected category: \(error)")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func fetchCategories() {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
      //  request.predicate = NSPredicate(format: "isVisible == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        do {
            categories = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch categories: \(error)")
            categories = []
        }
    }

    private func fetchOrCreateCategory(named name: String) -> Category {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        do {
            if let match = try viewContext.fetch(request).first {
                return match
            }
        } catch {
            print("❌ Fetch error: \(error)")
        }

        let newCategory = Category(context: viewContext)
        newCategory.name = name
        newCategory.id = UUID()
        return newCategory
    }
}



