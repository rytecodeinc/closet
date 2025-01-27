//
//  ItemGridView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//


import SwiftUI
import UIKit
import CoreData
import Combine

struct ItemGridView: View {
    @ObservedObject var filterModel: ItemFilterModel
    var wardrobeType: String
    var selectedWardrobe: Wardrobe
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var closetItems: [Item] = []
    @State private var isImagePickerPresented = false
    @State private var pickedImage: UIImage? = nil
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var path = NavigationPath()
    @State private var selectedTab: String = "Items"
    
    @State private var outfits: [Outfit] = []
    @State private var sortAscending: Bool = false // false = descending (newest first), true = ascending (oldest first)

    let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    // Computed property to track filter changes
    private var filterKey: String {
        var key = ""
        key += filterModel.selectedColors.sorted().joined(separator: ",")
        key += filterModel.selectedSeasons.sorted().joined(separator: ",")
        key += filterModel.selectedBrand?.objectID.uriRepresentation().absoluteString ?? ""
        key += filterModel.selectedTags.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        key += filterModel.minPrice?.description ?? ""
        key += filterModel.maxPrice?.description ?? ""
        key += filterModel.selectedCategoryName ?? ""
        key += filterModel.selectedSubcategoryName ?? ""
        key += filterModel.selectedSizeValue ?? ""
        key += filterModel.selectedLocation?.objectID.uriRepresentation().absoluteString ?? ""
        if filterModel.filterByWeight {
            // Include user weight in key so it refreshes when user updates their weight
            let userWeightKg = UserDefaults.standard.double(forKey: "userWeightKg")
            key += "weight:\(userWeightKg)"
        }
        return key
    }

    var body: some View {
        VStack(spacing: 0) {
          //  Divider()
            UnderlineTabBar(
                selectedTab: $selectedTab,
                tabs: ["Items (\(closetItems.count))", "Outfits (\(outfits.count))"]
            )
            
         /*   if !isControlsHidden {
                ControlsBar
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .transition(
                        .asymmetric(
                            insertion: .push(from: .top),
                            removal: .push(from: .bottom)
                        )
                    )
            }*/
            
            TabView(selection: $selectedTab) {
                itemsTab.tag("Items")
                outfitsTab.tag("Outfits")
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchItems()
            fetchOutfits()
        }
        .onChange(of: filterKey) {
            fetchItems()
        }
        .onChange(of: filterModel.filterByWeight) {
            fetchItems()
        }
        .onChange(of: selectedWardrobe.objectID) {
            fetchItems()
            fetchOutfits()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { notification in
            // Refresh items when context saves (items added/deleted/updated elsewhere)
            if let context = notification.object as? NSManagedObjectContext,
               context === viewContext || context.parent === viewContext {
                fetchItems()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                NavigationLink(destination: ItemFilterView(filterModel: filterModel)) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                Menu {
                    Button {
                        sortAscending = false
                        fetchItems()
                        fetchOutfits()
                    } label: {
                        Label("Newest First", systemImage: !sortAscending ? "checkmark" : "")
                    }
                    Button {
                        sortAscending = true
                        fetchItems()
                        fetchOutfits()
                    } label: {
                        Label("Oldest First", systemImage: sortAscending ? "checkmark" : "")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedTab == "Items" {
                    HStack(spacing: 16) {
                        NavigationLink(destination: ItemDraftsView()) {
                            Image(systemName: "folder")
                        }
                        NavigationLink(
                            destination: ItemAddView(parentContext: viewContext, selectedWardrobe: selectedWardrobe)
                        ) {
                            Image(systemName: "plus")
                        }
                    }
                } else if selectedTab == "Outfits" {
                    HStack(spacing: 16) {
                        NavigationLink(destination: OutfitDraftsView(wardrobeType: wardrobeType, selectedWardrobe: selectedWardrobe)) {
                            Image(systemName: "folder")
                        }
                        NavigationLink(destination: OutfitAddView(wardrobeType: wardrobeType, initialWardrobe: selectedWardrobe)) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(
                image: $pickedImage,
                sourceType: $imagePickerSource,
                allowsEditing: true
            ) { image in
                if let image = image {
                    createNewItem(with: image, in: selectedWardrobe)
                }
                isImagePickerPresented = false
            }
        }
    }

/*    private var ControlsBar: some View {
        HStack {
            NavigationLink(destination: FilterView(filterModel: filterModel)) {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            Spacer()
            Image(systemName: "arrow.up.arrow.down")
            Spacer()
            Image(systemName: "square.grid.3x2")
            Spacer()
            NavigationLink(
                destination: ItemAddView(parentContext: viewContext, selectedWardrobe: selectedWardrobe)
            ) {
                Image(systemName: "plus")
            }
        }
      //  .font(.system(size: 20))
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }*/
    
    // MARK: - Core Data fetch
    func fetchItems() {
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.timestamp, ascending: sortAscending)]
        
        // Build predicate from filterModel, but exclude wardrobe filter since we handle it separately below
        var subpredicates: [NSPredicate] = []
        
        // Add all filter predicates except wardrobe (we'll handle wardrobe separately)
        if !filterModel.selectedColors.isEmpty {
            let colorPredicate = NSPredicate(format: "ANY colors.name IN %@", Array(filterModel.selectedColors))
            subpredicates.append(colorPredicate)
        }
        if !filterModel.selectedSeasons.isEmpty {
            let seasonPredicate = NSPredicate(format: "ANY seasons.name IN %@", Array(filterModel.selectedSeasons))
            subpredicates.append(seasonPredicate)
        }
        if let brand = filterModel.selectedBrand, let brandName = brand.name, !brandName.isEmpty {
            let brandPredicate = NSPredicate(format: "brand.name ==[c] %@", brandName)
            subpredicates.append(brandPredicate)
        }
        if let minPrice = filterModel.minPrice {
            let minPricePredicate = NSPredicate(format: "price.amount >= %@", minPrice as NSDecimalNumber)
            subpredicates.append(minPricePredicate)
        }
        if let maxPrice = filterModel.maxPrice {
            let maxPricePredicate = NSPredicate(format: "price.amount <= %@", maxPrice as NSDecimalNumber)
            subpredicates.append(maxPricePredicate)
        }
        if !filterModel.selectedTags.isEmpty {
            let tagNames = filterModel.selectedTags.compactMap { $0.name }
            let tagPredicate = NSPredicate(format: "ANY tags.name IN %@", tagNames)
            subpredicates.append(tagPredicate)
        }
        // Handle category/subcategory filtering
        if let subcategoryName = filterModel.selectedSubcategoryName, !subcategoryName.isEmpty,
           let categoryName = filterModel.selectedCategoryName, !categoryName.isEmpty {
            // Filter by subcategory (which also implies the category)
            let subcategoryPredicate = NSPredicate(format: "subcategory.name ==[c] %@ AND category.name ==[c] %@", subcategoryName, categoryName)
            subpredicates.append(subcategoryPredicate)
        } else if let categoryName = filterModel.selectedCategoryName, !categoryName.isEmpty {
            // Filter by category only
            let categoryPredicate = NSPredicate(format: "category.name ==[c] %@", categoryName)
            subpredicates.append(categoryPredicate)
        }
        if let sizeValue = filterModel.selectedSizeValue, !sizeValue.isEmpty {
            let sizePredicate = NSPredicate(format: "size.value == %@", sizeValue)
            subpredicates.append(sizePredicate)
        }
        if let location = filterModel.selectedLocation {
            let locationPredicate = NSPredicate(format: "location == %@", location)
            subpredicates.append(locationPredicate)
        }
        
        // Weight filter - only show items that can support user's weight
        if filterModel.filterByWeight {
            let userWeightKg = UserDefaults.standard.double(forKey: "userWeightKg")
            if userWeightKg > 0 {
                // Show ONLY items where:
                // - Item has weight set (weight != nil) AND
                // - Item's max wearable weight <= user's weight
                // Logic: Item weight = max wearable weight the item can support
                // If item.weight > userWeight, the item CANNOT support the user (user is too heavy)
                // If item.weight <= userWeight, the item CAN support the user
                // Items without weight are EXCLUDED when filter is active
                // Note: weight is stored in kg in Core Data
                let weightExistsPredicate = NSPredicate(format: "weight != nil")
                let weightSupportedPredicate = NSPredicate(format: "weight <= %@", userWeightKg as NSNumber)
                
                // weight != nil AND weight <= userWeight
                let weightPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [weightExistsPredicate, weightSupportedPredicate])
                
                subpredicates.append(weightPredicate)
                print("🔍 Weight filter active: showing ONLY items with max wearable weight <= \(String(format: "%.2f", userWeightKg)) kg (excluding items without weight)")
                print("🔍 Weight predicate: \(weightPredicate)")
            } else {
                print("⚠️ Weight filter enabled but user weight not set in Profile")
            }
            // If user hasn't set their weight, don't filter (show all items)
        }
        
        // Handle wardrobe filtering: use filterModel.selectedWardrobes if set, otherwise use selectedWardrobe
        let wardrobePredicate: NSPredicate
        if !filterModel.selectedWardrobes.isEmpty {
            // If user selected specific wardrobes in filter, use those
            wardrobePredicate = NSPredicate(format: "ANY wardrobes IN %@", Array(filterModel.selectedWardrobes))
        } else {
            // Otherwise, use the view's selected wardrobe
            wardrobePredicate = NSPredicate(format: "ANY wardrobes == %@", selectedWardrobe)
        }
        subpredicates.append(wardrobePredicate)
        
        // Exclude drafts from item listings
        let draftPredicate = NSPredicate(format: "isDraft != YES")
        subpredicates.append(draftPredicate)
        
        // Combine all predicates
        let finalPredicate: NSPredicate
        if subpredicates.count == 1 {
            finalPredicate = subpredicates.first!
        } else {
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
        request.predicate = finalPredicate
        
        // Debug: Log predicate if weight filter is active
        if filterModel.filterByWeight {
            print("🔍 Final predicate: \(finalPredicate)")
        }
        
        do {
            let results = try viewContext.fetch(request)
            
            // Debug: Log results if weight filter is active
            if filterModel.filterByWeight {
                let userWeightKg = UserDefaults.standard.double(forKey: "userWeightKg")
                print("🔍 Fetched \(results.count) items with weight filter")
                // Sample a few items to check their weights
                for (index, item) in results.prefix(5).enumerated() {
                    if let weight = item.primitiveValue(forKey: "weight") as? Double {
                        print("🔍 Item \(index + 1): weight = \(String(format: "%.2f", weight)) kg (>= \(String(format: "%.2f", userWeightKg))? \(weight >= userWeightKg))")
                    } else {
                        print("🔍 Item \(index + 1): weight = nil (no limit)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.closetItems = results
            }
        } catch {
            print("❌ Failed to fetch items: \(error)")
            if let nsError = error as NSError? {
                print("❌ Error details: \(nsError.userInfo)")
            }
            DispatchQueue.main.async {
                self.closetItems = []
            }
        }
    }
    
    func fetchOutfits() {
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.timestamp, ascending: sortAscending)]
        // Exclude drafts from outfit listings
        request.predicate = NSPredicate(format: "isDraft != YES")

        do {
            let allOutfits = try viewContext.fetch(request)
            let filtered = allOutfits.filter { outfit in
                (outfit.items as? Set<Item>)?.contains(where: { $0.wardrobes?.contains(selectedWardrobe) ?? false }) ?? false
            }
            DispatchQueue.main.async {
                self.outfits = filtered
            }
        } catch {
            print("Failed to fetch outfits: \(error)")
            DispatchQueue.main.async {
                self.outfits = []
            }
        }
    }


    // MARK: - Create New Item
    private func createNewItem(with image: UIImage, in wardrobe: Wardrobe) {
        let item = Item(context: viewContext)
        item.id = UUID()
        item.timestamp = Date()
        
        if let imageData = image.pngData() {
            let photo = Photo(context: viewContext)
            photo.data = imageData
            photo.isPrimary = true
            photo.id = UUID()
            photo.item = item
        }

                wardrobe.addToItems(item)   // <-- attach to the correct wardrobe

        do {
            try viewContext.save()
            print("✅ New item saved in \(wardrobe.name ?? "unknown wardrobe")")
            path.append(item)
            // Refresh items after adding new one
            fetchItems()
        } catch {
            print("❌ Failed to save new item: \(error.localizedDescription)")
        }
    }
    
    private var itemsTab: some View {
        Group {
            if closetItems.isEmpty {
                EmptyItemStateView()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(closetItems, id: \.objectID) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemView(item: item)
                                  /*  .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .preference(
                                                    key: ScrollOffsetPreferenceKey.self,
                                                    value: geo.frame(in: .named("scroll")).minY < 100 ? index : nil
                                                )
                                        }
                                    )*/
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            /*    .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { topIndex in
                    guard let topIndex = topIndex else { return }
                    handleScroll(topIndex)
                }*/
            }
        }
    }

    private var outfitsTab: some View {
        Group {
            if outfits.isEmpty {
                EmptyOutfitStateView()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(outfits, id: \.objectID) { outfit in
                            NavigationLink(destination: OutfitDetailView(outfit: outfit)) {
                                OutfitView(outfit: outfit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

  /*  private func handleScroll(_ topIndex: Int) {
        if let last = currentTopIndex {
            if topIndex > last && !isControlsHidden {
                // Scrolling down
                withAnimation(.easeInOut(duration: 0.25)) {
                    isControlsHidden = true
                }
            } else if topIndex < last && isControlsHidden {
                // Scrolling up
                withAnimation(.easeInOut(duration: 0.25)) {
                    isControlsHidden = false
                }
            }
        }
        currentTopIndex = topIndex
    }*/
}

/* MARK: - Scroll Offset PreferenceKey
struct ScrollOffsetPreferenceKey: PreferenceKey {
    typealias Value = Int?
    static var defaultValue: Int? = nil
    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        value = value ?? nextValue()
    }
}*/
