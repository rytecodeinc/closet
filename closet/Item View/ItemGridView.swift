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

    @Environment(\.managedObjectContext) private var viewContext

    @State private var isImagePickerPresented = false
    @State private var pickedImage: UIImage? = nil
    @State private var path = NavigationPath()

    let gridItems = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    init(predicate: NSPredicate? = nil, filterModel: FilterModel) {
        self.filterModel = filterModel
        _closetItems = FetchRequest(
            entity: Item.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
            predicate: predicate ?? NSPredicate(value: true)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                if closetItems.isEmpty {
                    EmptyStateView()
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridItems, spacing: 1) {
                            ForEach(closetItems, id: \.self) { item in
                                ItemView(item: item)
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: FilterView(filterModel: filterModel)) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isImagePickerPresented = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isImagePickerPresented) {
                ImagePicker(image: $pickedImage, allowsEditing: true) { image in
                    if let image = image {
                        createNewItem(with: image)
                    }
                    isImagePickerPresented = false
                }
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
        }
    }

    private func createNewItem(with image: UIImage) {
        let item = Item(context: viewContext)
        item.id = UUID()
        item.timestamp = Date()
        item.isWishlist = false

        if let imageData = image.jpegData(compressionQuality: 0.8) {
            item.image = imageData
        }

        do {
            try viewContext.save()
            print("✅ New item saved with photo")
            path.append(item) // Trigger the navigation
        } catch {
            print("❌ Failed to save new item: \(error.localizedDescription)")
        }
    }
}






