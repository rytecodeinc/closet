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
        ZStack(alignment: .topTrailing) {
            if let itemImage = displayImage {
                Image(uiImage: itemImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .clipped()
                  //  .border(.gray.opacity(0.3), width: 0.5)
                    .background(Color(red: 247/255, green: 247/255, blue: 247/255))


                   /* .background(LinearGradient(colors: [.white, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomLeading))*/
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .clipped()
                    .foregroundColor(.gray)
                   /* .background(LinearGradient(colors: [.white, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomLeading))*/
            }

            let isWishlist = (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
            
            if isWishlist {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .padding(10)
            }
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

// MARK: Migration
func migrateWishlistItems(context: NSManagedObjectContext) {
    // Fetch (or create) Closet wardrobe
    let closetWardrobe: Wardrobe = {
        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        request.predicate = NSPredicate(format: "type == %@", "closet")
        if let existing = try? context.fetch(request).first {
            return existing
        } else {
            let newWardrobe = Wardrobe(context: context)
            newWardrobe.id = UUID()
            newWardrobe.type = "closet"
            newWardrobe.name = "Closet"
            newWardrobe.timestamp = Date()
            return newWardrobe
        }
    }()
    
    // Fetch (or create) Wishlist wardrobe
    let wishlistWardrobe: Wardrobe = {
        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        request.predicate = NSPredicate(format: "type == %@", "wishlist")
        if let existing = try? context.fetch(request).first {
            return existing
        } else {
            let newWardrobe = Wardrobe(context: context)
            newWardrobe.id = UUID()
            newWardrobe.type = "wishlist"
            newWardrobe.name = "Wishlist"
            newWardrobe.timestamp = Date()
            return newWardrobe
        }
    }()
    
    // Fetch all items
    let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
    
    do {
        let allItems = try context.fetch(itemRequest)
        
        for item in allItems {
            // Convert wardrobes to mutable set
            var currentWardrobes = item.wardrobes as? Set<Wardrobe> ?? []
            
            // Assign Wishlist if flagged
            if item.isWishlist {
                currentWardrobes.insert(wishlistWardrobe)
            }
            
            // Assign Closet if item has no wardrobes yet
            if currentWardrobes.isEmpty {
                currentWardrobes.insert(closetWardrobe)
            }
            
            item.wardrobes = currentWardrobes as NSSet
        }
        
        try context.save()
        print("✅ Migration completed successfully!")
        
    } catch {
        print("❌ Migration failed:", error)
    }
}


