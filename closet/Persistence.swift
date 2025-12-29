//
//  Persistence.swift
//  closet
//
//  Created by Dan Warner on 4/12/25.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Seed default data (colors, seasons, categories, subcategories, sizes, wardrobes)
        DataSeeder(context: viewContext)
        
        // Seed two wardrobes
        let closet = Wardrobe(context: viewContext)
        closet.id = UUID()
        closet.name = "Closet"
        closet.type = "closet"
        
        let wishlist = Wardrobe(context: viewContext)
        wishlist.id = UUID()
        wishlist.name = "Wishlist"
        wishlist.type = "wishlist"
        
        // Seed items and attach them to one of the wardrobes
        for i in 0..<11 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
            
            if i < 5 {
                newItem.isWishlist = true
                wishlist.addToItems(newItem) // Attach to wishlist wardrobe
            } else {
                newItem.isWishlist = false
                closet.addToItems(newItem) // Attach to closet wardrobe
            }
        }

        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer
    
    private static let hasSeededDataKey = "hasSeededDefaultData_v1"

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "closet")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { [weak container] (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
            
            // Seed data once, in background (if not in-memory store)
            if !inMemory, let container = container {
                Self.seedInitialDataIfNeeded(container: container)
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    private static func seedInitialDataIfNeeded(container: NSPersistentContainer) {
        let alreadySeeded = UserDefaults.standard.bool(forKey: hasSeededDataKey)
        print("🌱 Checking if data needs seeding... Already seeded: \(alreadySeeded)")
        
        // Skip if already seeded (optimization)
        guard !alreadySeeded else {
            print("⏭️ Skipping seeding - already marked as complete")
            return
        }
        
        print("🌱 Starting data seeding...")
        
        // Use view context for seeding - it's a one-time operation on first launch
        // This ensures changes are immediately available to the UI
        // Dispatch to main queue since view context requires main thread
        DispatchQueue.main.async {
            let context = container.viewContext
            do {
                // DataSeeder already checks if data exists before inserting
                // So it's safe to call even if partially seeded
                print("🌱 Calling DataSeeder...")
                DataSeeder(context: context)
                
                // Save the context
                print("🌱 Saving context...")
                try context.save()
                
                // Mark as seeded after successful save
                UserDefaults.standard.set(true, forKey: hasSeededDataKey)
                print("✅ Default data seeding completed and saved")
            } catch {
                print("❌ Failed to seed data: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                // Don't mark as seeded if save failed
                UserDefaults.standard.removeObject(forKey: hasSeededDataKey)
            }
        }
    }
}
