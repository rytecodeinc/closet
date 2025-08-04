//
//  ItemView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//

import SwiftUI
import CoreData

struct ItemView: View {
    @ObservedObject var item: Item
    @State private var isActive: Bool = false
    @Environment(\.managedObjectContext) private var viewContext

    var displayImage: UIImage? {
        if let primaryImageData = item.photos?.first(where: { ($0 as? Photo)?.isPrimary == true }) as? Photo {
            return UIImage(data: primaryImageData.data ?? Data())
        } else if let fallbackImage = item.image {
            return UIImage(data: fallbackImage)
        } else {
            return nil
        }
    }

    var body: some View {
        ZStack {
            NavigationLink(destination: ItemDetailView(item: item), isActive: $isActive) {
                EmptyView()
            }
            .hidden()

            if let itemImage = displayImage {
                Image(uiImage: itemImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .clipped()
                    .foregroundColor(.gray)
            }

            
            if item.isWishlist {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .padding(10)
                    .offset(x: 45, y: -45)
            }
        }
        .onTapGesture {
            isActive = true
        }
    }

    private func deleteItem() {
        viewContext.delete(item)
        do {
            try viewContext.save()
        } catch {
            print("Failed to delete item: \(error.localizedDescription)")
        }
    }
}

func migrateItemImages(context: NSManagedObjectContext) {
    let fetchRequest: NSFetchRequest<Item> = Item.fetchRequest()

    do {
        let items = try context.fetch(fetchRequest)
        for item in items {
            if let existingImageData = item.image {
                let newImage = Photo(context: context)
                newImage.data = existingImageData
                newImage.type = "default"
                newImage.isPrimary = true
                newImage.item = item

                // Remove the old attribute's value
                 item.image = nil
            }
        }
        print("Migration successful!!!")
        try context.save()
        
    } catch {
        print("Migration failed: \(error)")
    }
}
