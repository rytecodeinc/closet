//
//  ItemGridView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//


import SwiftUI
import UIKit
import CoreData

struct ItemGridView: View {
    @FetchRequest var closetItems: FetchedResults<Item>
    @ObservedObject var filterModel: FilterModel
    var wardrobeType: String
    var selectedWardrobe: Wardrobe
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isImagePickerPresented = false
    @State private var pickedImage: UIImage? = nil
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var path = NavigationPath()
    
    init(filterModel: FilterModel, wardrobeType: String, selectedWardrobe: Wardrobe) {
        self.filterModel = filterModel
        self.wardrobeType = wardrobeType
        self.selectedWardrobe = selectedWardrobe
        
        // Base filter from the filterModel
        let basePredicate = makePredicate(for: filterModel)
        
        // Always filter by selected wardrobe
        let wardrobePredicate = NSPredicate(format: "ANY wardrobes == %@", selectedWardrobe)
        
        var predicates: [NSPredicate] = []
        if let base = basePredicate { predicates.append(base) }
        predicates.append(wardrobePredicate)
        
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        _closetItems = FetchRequest(
            entity: Item.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
            predicate: finalPredicate
        )
    }

    let gridItems = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        VStack {
            if closetItems.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridItems, spacing: 2) {
                        ForEach(closetItems, id: \.objectID) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemView(item: item)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: FilterView(filterModel: filterModel)) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
           /* ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: ItemAddView(parentContext: viewContext, wardrobeType: wardrobeType)) {
                    Image(systemName: "plus")
                }
            }*/
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
        } catch {
            print("❌ Failed to save new item: \(error.localizedDescription)")
        }
    }

}








