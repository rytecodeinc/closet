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
    // Check if migration has already been completed
    let migrationKey = "hasMigratedItemImages"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    let fetchRequest: NSFetchRequest<Item> = Item.fetchRequest()

    do {
        let items = try context.fetch(fetchRequest)
        var hasChanges = false
        
        for item in items {
            if let existingImageData = item.image {
                let newImage = Photo(context: context)
                newImage.data = existingImageData
                newImage.type = "default"
                newImage.isPrimary = true
                newImage.item = item

                // Remove the old attribute's value
                item.image = nil
                hasChanges = true
            }
        }
        
        if hasChanges {
            try context.save()
            print("✅ Item images migration successful!")
        }
        
        // Mark migration as completed
        UserDefaults.standard.set(true, forKey: migrationKey)
        
    } catch {
        print("❌ Item images migration failed: \(error)")
    }
}

// MARK: - Deduplicate Wardrobes
func deduplicateWardrobes(context: NSManagedObjectContext) {
    do {
        // Fetch all wardrobes
        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        let allWardrobes = try context.fetch(request)
        
        print("🔍 Checking \(allWardrobes.count) wardrobes for duplicates...")
        
        // Group wardrobes by name (case-insensitive, trimmed) and type
        // This will catch duplicates with the same name and type
        var wardrobesByNameAndType: [String: [Wardrobe]] = [:]
        for wardrobe in allWardrobes {
            let name = (wardrobe.name ?? "unnamed").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let type = wardrobe.type ?? "unknown"
            let key = "\(name)|\(type)"
            wardrobesByNameAndType[key, default: []].append(wardrobe)
        }
        
        var hasChanges = false
        var deletedCount = 0
        
        // For each group, if there are duplicates, merge them
        for (key, wardrobes) in wardrobesByNameAndType {
            if wardrobes.count > 1 {
                // Keep the wardrobe with the most items (or oldest if equal)
                let primaryWardrobe = wardrobes.max { wardrobe1, wardrobe2 in
                    let count1 = wardrobe1.items?.count ?? 0
                    let count2 = wardrobe2.items?.count ?? 0
                    if count1 != count2 {
                        return count1 < count2
                    }
                    // If same item count, prefer the older one (earlier timestamp)
                    let date1 = wardrobe1.timestamp ?? Date.distantFuture
                    let date2 = wardrobe2.timestamp ?? Date.distantFuture
                    return date1 > date2
                } ?? wardrobes.first!
                
                let duplicates = wardrobes.filter { $0 != primaryWardrobe }
                
                let wardrobeName = primaryWardrobe.name ?? "unnamed"
                let wardrobeType = primaryWardrobe.type ?? "unknown"
                print("🔧 Found \(duplicates.count) duplicate wardrobes named '\(wardrobeName)' (type: '\(wardrobeType)'). Merging into primary wardrobe.")
                
                // Merge items from duplicates into primary wardrobe
                for duplicate in duplicates {
                    if let items = duplicate.items as? Set<Item> {
                        print("   Merging \(items.count) items from duplicate '\(duplicate.name ?? "unnamed")'")
                        for item in items {
                            // Remove from duplicate and add to primary
                            duplicate.removeFromItems(item)
                            primaryWardrobe.addToItems(item)
                        }
                    }
                    // Delete the duplicate wardrobe
                    context.delete(duplicate)
                    deletedCount += 1
                }
                
                hasChanges = true
            }
        }
        
        if hasChanges {
            try context.save()
            print("✅ Wardrobe deduplication completed! Removed \(deletedCount) duplicate wardrobe(s).")
        } else {
            print("✅ No duplicate wardrobes found.")
        }
        
    } catch {
        print("❌ Wardrobe deduplication failed: \(error)")
    }
}

// MARK: Migration
func migrateWishlistItems(context: NSManagedObjectContext) {
    // Check if migration has already been completed
    let migrationKey = "hasMigratedWishlistItems"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
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
        var hasChanges = false
        
        for item in allItems {
            // Convert wardrobes to mutable set
            var currentWardrobes = item.wardrobes as? Set<Wardrobe> ?? []
            let originalCount = currentWardrobes.count
            
            // Assign Wishlist if flagged
            if item.isWishlist {
                currentWardrobes.insert(wishlistWardrobe)
            }
            
            // Assign Closet if item has no wardrobes yet
            if currentWardrobes.isEmpty {
                currentWardrobes.insert(closetWardrobe)
            }
            
            // Only update if something changed
            if currentWardrobes.count != originalCount || item.isWishlist {
                item.wardrobes = currentWardrobes as NSSet
                hasChanges = true
            }
        }
        
        if hasChanges {
            try context.save()
            print("✅ Wishlist items migration completed successfully!")
        }
        
        // Mark migration as completed
        UserDefaults.standard.set(true, forKey: migrationKey)
        
    } catch {
        print("❌ Wishlist items migration failed:", error)
    }
}


