//
//  CategorySelectionView 2.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//


struct CategorySelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategoryName: String?
    @State private var selectedSubcategoryName: String?
    @State private var categories: [Category] = []
    @State private var expanded: Set<NSManagedObjectID> = []

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
                        let subs = sortedSubcategories(for: category)
                        let hasSubs = !subs.isEmpty
                        let isOpen = expanded.contains(category.objectID)

                        // Category row
                        HStack {
                            Text(name)
                                .foregroundColor(.black)
                                .onTapGesture {
                                    // Select the category (does NOT affect expansion)
                                    if selectedCategoryName == name && selectedSubcategoryName == nil {
                                        selectedCategoryName = nil
                                    } else {
                                        selectedCategoryName = name
                                        selectedSubcategoryName = nil
                                    }
                                }

                            Spacer()
                            
                            if selectedCategoryName == name && selectedSubcategoryName == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                            
                            if hasSubs {
                                // Chevron is the expand/collapse button
                                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                    .onTapGesture {
                                        toggle(category)
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggle(category)
                        }

                        // Subcategory rows (only when expanded)
                        if isOpen {
                            ForEach(subs, id: \.self) { sub in
                                let subName = sub.name ?? ""
                                HStack {
                                    Text(subName)
                                        .padding(.leading, 20)
                                        .foregroundColor(.black)
                                    Spacer()
                                    if selectedCategoryName == name && selectedSubcategoryName == subName {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Toggle this subcategory selection
                                    let isThisSelected = (selectedCategoryName == name && selectedSubcategoryName == subName)
                                    if isThisSelected {
                                        // Deselect completely
                                        selectedCategoryName = nil
                                        selectedSubcategoryName = nil
                                    } else {
                                        // Select this subcategory (and its parent)
                                        selectedCategoryName = name
                                        selectedSubcategoryName = subName
                                    }
                                }
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

            if let currentCat = item.category,
               let currentSub = item.subcategory,
               currentSub.category == currentCat {
                selectedSubcategoryName = currentSub.name
                if let match = categories.first(where: { $0.objectID == currentCat.objectID }) {
                    expanded.insert(match.objectID)
                }
            } else {
                selectedSubcategoryName = nil
            }
        }
        .onDisappear {
            // Apply selection to the item object (but DON'T save context)
            applySelectionToItem()
            // Let the parent view (ItemAddView) decide when to save
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Apply Selection (without saving)
    
    private func applySelectionToItem() {
        guard let catName = selectedCategoryName, !catName.isEmpty else {
            item.category = nil
            item.subcategory = nil
            return
        }

        let category = fetchOrCreateCategory(named: catName)
        item.category = category

        if let subName = selectedSubcategoryName, !subName.isEmpty,
           let sub = fetchSubcategory(named: subName, in: category) {
            item.subcategory = sub
        } else {
            item.subcategory = nil
        }
        
        // CRITICAL: Do NOT save here
        // The changes stay in the child context
        // ItemAddView will save when user taps "Save" or rollback when user taps "Cancel"
    }

    // MARK: - Fetchers

    private func fetchCategories() {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        do {
            categories = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch categories: \(error)")
            categories = []
        }
    }

    private func sortedSubcategories(for category: Category) -> [Subcategory] {
        let set = (category.subcategories as? Set<Subcategory>) ?? []
        return set.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return ($0.name ?? "") < ($1.name ?? "")
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
            print("❌ Fetch category error: \(error)")
        }

        let newCategory = Category(context: viewContext)
        newCategory.name = name
        newCategory.id = UUID()
        return newCategory
    }

    private func fetchSubcategory(named name: String, in category: Category) -> Subcategory? {
        let req: NSFetchRequest<Subcategory> = Subcategory.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "name ==[c] %@ AND category == %@", name, category)
        return try? viewContext.fetch(req).first
    }

    // MARK: - UI State

    private func toggle(_ category: Category) {
        let id = category.objectID
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }
}