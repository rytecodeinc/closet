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
    var collectionType: String
    
    @Environment(\.managedObjectContext) private var viewContext

    @State private var isImagePickerPresented = false
    @State private var pickedImage: UIImage? = nil
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var path = NavigationPath()
    
    init(predicate: NSPredicate? = nil, filterModel: FilterModel, collectionType: String) {
        self.filterModel = filterModel
        self.collectionType = collectionType

        let basePredicate = makePredicate(for: filterModel)
        
        // ✅ Filter items by relationship to Collection entity
        let collectionPredicate = NSPredicate(format: "ANY collections.type == %@", collectionType)
        
        let finalPredicate = basePredicate.map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [$0, collectionPredicate])
        } ?? collectionPredicate

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
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: ItemAddView(parentContext: viewContext, collectionType: collectionType)) {
                    Image(systemName: "plus")
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
                    createNewItem(with: image)
                }
                isImagePickerPresented = false
            }
        }
    }

    // MARK: - Create New Item
    private func createNewItem(with image: UIImage) {
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

        // ✅ Attach to the appropriate Collection
        let request: NSFetchRequest<Collection> = Collection.fetchRequest()
        request.predicate = NSPredicate(format: "type == %@", collectionType)
        if let collection = try? viewContext.fetch(request).first {
            collection.addToItems(item)
        }

        do {
            try viewContext.save()
            print("✅ New item saved with photo in \(collectionType)")
            path.append(item)
        } catch {
            print("❌ Failed to save new item: \(error.localizedDescription)")
        }
    }
}








