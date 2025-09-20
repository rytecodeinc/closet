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
    var isWishlist: Bool
    
    @Environment(\.managedObjectContext) private var viewContext

    @State private var isImagePickerPresented = false
    @State private var pickedImage: UIImage? = nil
    @State private var imagePickerSource:  UIImagePickerController.SourceType = .photoLibrary
    @State private var path = NavigationPath()
    
    init(predicate: NSPredicate? = nil, filterModel: FilterModel, isWishlist: Bool) {
        self.filterModel = filterModel
        self.isWishlist = isWishlist

        let basePredicate = makePredicate(for: filterModel)

        let wishlistPredicate = NSPredicate(format: "isWishlist == %@", NSNumber(value: isWishlist))
        
        let finalPredicate = basePredicate.map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [$0, wishlistPredicate])
        } ?? wishlistPredicate

        _closetItems = FetchRequest(
            entity: Item.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
            predicate: finalPredicate
        )
    }

    let gridItems = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
       // NavigationStack(path: $path) {
            VStack {
                if closetItems.isEmpty {
                    EmptyStateView()
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridItems, spacing: 0) {
                            ForEach(closetItems, id: \.objectID) { item in
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    ItemView(item: item)
                                }
                            }
                           //background is set in ItemView
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
                    NavigationLink(destination: ItemAddView(parentContext: viewContext, isWishlist: isWishlist)) {
                        Image(systemName: "plus")
                    }
                    /*
                    Menu {
                        Button() {
                            imagePickerSource = .camera
                            isImagePickerPresented = true
                        } label: {
                            Label("Take New Photo", systemImage: "camera")
                        }
                        
                        Button() {
                            imagePickerSource = .photoLibrary
                            isImagePickerPresented = true
                        } label: {
                            Label("Choose from Library", systemImage: "photo.on.rectangle.angled")
                        }
                        
                    } label: {
                        Image(systemName: "plus")
                    }*/
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
          /*  .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }*/
       // }
    }

    private func createNewItem(with image: UIImage) {
        let item = Item(context: viewContext)
        item.id = UUID()
        item.timestamp = Date()
        item.isWishlist = isWishlist
        
        if let imageData = image.pngData() {
            let photo = Photo(context: viewContext)
            photo.data = imageData
            photo.isPrimary = true
            photo.id = UUID()
            photo.item = item // link photo to item
        }

        do {
            try viewContext.save()
            print("✅ New item saved with photo")
            path.append(item)
        } catch {
            print("❌ Failed to save new item: \(error.localizedDescription)")
        }
    }
}







