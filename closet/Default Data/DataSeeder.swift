//
//  DataSeeder.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import Foundation
import CoreData

struct DataSeeder {
    
    // MARK: - Constants

    private static let defaultColorNames: [String] = [
        "White", "Black", "Beige", "Red", "Orange",
        "Yellow", "Green", "Blue", "Purple", "Pink",
        "Brown", "Gray", "Silver", "Gold"
    ]

    private static let defaultSeasonNames: [String] = [
        "Spring", "Summer", "Fall", "Winter"
    ]

    private static let defaultCategoryNames: [String] = [
        "Tops", "Bottoms", "Outerwear", "Shoes", "Accessories",
        "Dresses", "Suits", "Swimwear", "Activewear"
    ]//sets, intimates, loungewear
    
    private struct SizeBundle {
        let scale: String
        let values: [String]
    }
    
    // Common size sets
    private static let alphaSizes: [String]      = ["XXS", "XS", "S", "M", "L", "XL", "XXL"]
    private static let numericSizes: [String]   = ["00","0","2","4","6","8","10","12","14","16"]
    private static let shoeSizes: [String]  = ["5","5.5","6","6.5","7","7.5","8","8.5","9","9.5","10","10.5","11","11.5","12","12.5","13"]
    private static let oneSize: [String]         = ["One Size"]
    
    // Map Category.name -> (scale label, size values)
    private static let defaultSizesByCategory: [String: [SizeBundle]] = [
        "Tops":       [SizeBundle(scale: "Alpha (XXS-XXL)", values: alphaSizes)],
        "Outerwear":  [SizeBundle(scale: "Alpha (XXS-XXL)", values: alphaSizes)],
        "Activewear": [SizeBundle(scale: "Alpha (XXS-XXL)", values: alphaSizes)],
        "Bottoms":    [
            SizeBundle(scale: "US Numeric",        values: numericSizes),
            SizeBundle(scale: "Alpha (XXS-XXL)",   values: alphaSizes)
        ],
        "Dresses":    [
            SizeBundle(scale: "US Numeric",        values: numericSizes),
            SizeBundle(scale: "Alpha (XXS-XXL)",   values: alphaSizes)
        ],
        "Suits":      [SizeBundle(scale: "US Numeric", values: numericSizes)],
        "Swimwear":   [SizeBundle(scale: "Alpha (XXS-XXL)", values: alphaSizes)],
        "Accessories":[SizeBundle(scale: "One Size", values: oneSize)],
        "Shoes":      [SizeBundle(scale: "US Shoe", values: shoeSizes)],
    ]
    
    // MARK: - Init
    
    init(context: NSManagedObjectContext) {
        preloadDefaultColors(context: context)
        preloadDefaultSeasons(context: context)
        preloadDefaultCategories(context: context)
        preloadDefaultSubcategories(context: context)
        preloadDefaultSizes(context: context)
        preloadDefaultWardrobes(context: context)
    }

    // MARK: - Public Preloaders

    private func preloadDefaultColors(context: NSManagedObjectContext) {
        do {
            if try countColors(in: context) == 0 {
                try insertDefaultColors(in: context)
            }
            let names = try fetchAllColors(in: context).compactMap { $0.name }
            print("✅ Colors seeded or already present → \(names)")
        } catch {
            print("❌ Color seeding error:", error)
        }
    }

    private func preloadDefaultSeasons(context: NSManagedObjectContext) {
        do {
            if try countSeasons(in: context) == 0 {
                try insertDefaultSeasons(in: context)
            }
            let names = try fetchAllSeasons(in: context).compactMap { $0.name }
            print("✅ Seasons seeded or already present → \(names)")
        } catch {
            print("❌ Season seeding error:", error)
        }
    }

    private func preloadDefaultCategories(context: NSManagedObjectContext) {
        do {
            if try countCategories(in: context) == 0 {
                try insertDefaultCategories(in: context)
            }
            let names = try fetchAllCategories(in: context).compactMap { $0.name }
            print("✅ Categories seeded or already present → \(names)")
        } catch {
            print("❌ Category seeding error:", error)
        }
    }

    // MARK: - Color Helpers

    private func countColors(in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Color"))
    }

    private func insertDefaultColors(in context: NSManagedObjectContext) throws {
        for name in Self.defaultColorNames {
            let color = AppColor(context: context)
            color.name = name
            color.isVisible = true
        }
        try context.save()
    }

    private func fetchAllColors(in context: NSManagedObjectContext) throws -> [AppColor] {
        try context.fetch(NSFetchRequest<AppColor>(entityName: "Color"))
    }

    // MARK: - Season Helpers

    private func countSeasons(in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Season"))
    }

    private func insertDefaultSeasons(in context: NSManagedObjectContext) throws {
        for name in Self.defaultSeasonNames {
            let season = Season(context: context)
            season.name = name
            season.id   = UUID()
            season.isVisible = true
        }
        try context.save()
    }

    private func fetchAllSeasons(in context: NSManagedObjectContext) throws -> [Season] {
        try context.fetch(NSFetchRequest<Season>(entityName: "Season"))
    }

    // MARK: - Category Helpers

    private func countCategories(in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Category"))
    }

    private func insertDefaultCategories(in context: NSManagedObjectContext) throws {
        for name in Self.defaultCategoryNames {
            let category = Category(context: context)
            category.name = name
            category.id = UUID()
            category.isVisible = true
        }
        try context.save()
    }

    private func fetchAllCategories(in context: NSManagedObjectContext) throws -> [Category] {
        try context.fetch(NSFetchRequest<Category>(entityName: "Category"))
    }
    
    // MARK: SUBCATEGORIES
    // MARK: - Subcategories

    private static let defaultSubcategoriesByCategory: [String: [String]] = [
        "Tops":        ["T-Shirts", "Blouses", "Sweaters", "Tanks"],
        "Bottoms":     ["Jeans", "Trousers", "Skirts", "Shorts"],
        "Outerwear":   ["Jackets", "Coats", "Blazers"],
        "Dresses":     ["Mini", "Midi", "Maxi"],
        "Suits":       ["Skirt Suits", "Pant Suits"],
        "Swimwear":    ["One-Piece", "Bikini", "Cover-ups"],
        "Activewear":  ["Leggings", "Sports Bras", "Tops"],
        "Shoes":       ["Heels", "Flats", "Sneakers", "Boots", "Sandals"],
        "Accessories": ["Bags", "Belts", "Hats", "Scarves", "Jewelry"]
    ]

    // Call this from init AFTER categories preloaded:
    func preloadDefaultSubcategories(context: NSManagedObjectContext, forceReseed: Bool = false) {
        do {
            if forceReseed {
                try deleteAllSubcategories(in: context)
            }
            if try countSubcategories(in: context) == 0 {
                try insertDefaultSubcategories(in: context)
            }

            let total = try countSubcategories(in: context)
            print("✅ Subcategories seeded or already present → total rows: \(total)")
            #if DEBUG
            // Debug: print counts by category
            let cats = try fetchAllCategories(in: context)
            for c in cats {
                let count = (c.subcategories as? Set<Subcategory>)?.count ?? 0
                print("   • \(c.name ?? "<unnamed>"): \(count) subcategories")
            }
            #endif
        } catch {
            print("❌ Subcategory seeding error:", error)
        }
    }

    private func countSubcategories(in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Subcategory"))
    }

    private func deleteAllSubcategories(in context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Subcategory")
        let delete = NSBatchDeleteRequest(fetchRequest: fetch)
        try context.execute(delete)
        try context.save()
    }

    private func insertDefaultSubcategories(in context: NSManagedObjectContext) throws {
        let categories = try fetchAllCategories(in: context)

        // 👇 Build [lowercasedName: Category] without tuple inference
        let byName: [String: Category] = categories.reduce(into: [:]) { dict, cat in
            if let raw = cat.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                dict[raw.lowercased()] = cat
            }
        }

        var missing: [String] = []

        for (rawCatName, names) in Self.defaultSubcategoriesByCategory {
            let key = rawCatName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let category = byName[key] else {
                missing.append(rawCatName)
                continue
            }

            for (idx, rawName) in names.enumerated() {
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                if existingSubcategory(named: name, in: category, context: context) != nil { continue }

                let sub = Subcategory(context: context)
                sub.id = UUID()
                sub.name = name
                sub.isVisible = true
                sub.sortOrder = Int16(idx)
                sub.category = category
            }
        }

        if !missing.isEmpty {
            print("⚠️ Missing categories for subcategory seeding (name mismatch?): \(missing)")
        }

        try context.save()
    }


    private func existingSubcategory(named name: String, in category: Category, context: NSManagedObjectContext) -> Subcategory? {
        let req: NSFetchRequest<Subcategory> = Subcategory.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "name ==[c] %@ AND category == %@", name, category)
        return try? context.fetch(req).first
    }

    
    // Public entry point (match your other preloaders)
    func preloadDefaultSizes(context: NSManagedObjectContext, forceReseed: Bool = false) {
        do {
            if forceReseed {
                try deleteAllSizes(in: context)
            }
            
            // Run migration to deduplicate existing sizes if any exist
            // let sizeCount = try countSizes(in: context)
            // if sizeCount > 0 {
            //     try migrateDeduplicateSizes(in: context)
            // }
            
            if try countSizes(in: context) == 0 {
                try insertDefaultSizes(in: context)
            }
            let total = try countSizes(in: context)
            print("✅ Sizes seeded or already present → total rows: \(total)")
        } catch {
            print("❌ Size seeding error:", error)
        }
    }

    private func deleteAllSizes(in context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Size")
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetch)
        try context.execute(batchDelete)
        try context.save()
    }
    
    // MARK: - Migration: Deduplicate Sizes
    
    /// Migrates existing sizes to unique (value, scale) combinations
    /// - Removes duplicates by keeping one size per (value, scale) pair
    /// - Updates all Item.itemSize references to point to kept sizes
    /// - Sets category to nil on all sizes (sizes are now independent)
    // Disabled — preloadDefaultSizes call commented out.
    /*
    private func migrateDeduplicateSizes(in context: NSManagedObjectContext) throws {
        print("🔄 Starting size deduplication migration...")
        
        // Fetch all sizes
        let allSizesRequest: NSFetchRequest<Size> = Size.fetchRequest()
        let allSizes = try context.fetch(allSizesRequest)
        
        if allSizes.isEmpty {
            print("✅ No sizes to migrate")
            return
        }
        
        // Group sizes by (value, scale) combination
        var sizeGroups: [String: [Size]] = [:] // key: "value|scale", value: array of duplicate sizes
        
        for size in allSizes {
            guard let value = size.value, let scale = size.scale else { continue }
            let key = "\(value)|\(scale)"
            if sizeGroups[key] == nil {
                sizeGroups[key] = []
            }
            sizeGroups[key]?.append(size)
        }
        
        // For each group, keep one size and mark others for deletion
        var sizesToDelete: [Size] = []
        var valueToKeptSize: [String: Size] = [:] // Track which size we're keeping for each key
        
        for (key, sizes) in sizeGroups {
            guard !sizes.isEmpty else { continue }
            
            // Keep the first size (or one that's already being used by items)
            // Prefer a size that has items referencing it
            let sortedSizes = sizes.sorted { size1, size2 in
                let items1 = (size1.items as? Set<Item>)?.count ?? 0
                let items2 = (size2.items as? Set<Item>)?.count ?? 0
                return items1 > items2 // Prefer size with more items
            }
            
            guard let keptSize = sortedSizes.first else { continue }
            valueToKeptSize[key] = keptSize
            
            // Mark others for deletion (but first update item references)
            for size in sortedSizes.dropFirst() {
                // Update all items that reference this size to reference the kept size instead
                if let items = size.items as? Set<Item> {
                    for item in items {
                        item.itemSize = keptSize
                    }
                }
                sizesToDelete.append(size)
            }
        }
        
        // Update all sizes to have category = nil (sizes are now independent)
        for size in allSizes {
            size.category = nil
        }
        
        // Delete duplicate sizes
        for size in sizesToDelete {
            context.delete(size)
        }
        
        // Ensure unique sizes exist for all expected (value, scale) combinations
        let expectedSizes: [String: [String]] = [
            "Alpha (XXS-XXL)": ["XXS", "XS", "S", "M", "L", "XL", "XXL"],
            "US Numeric": ["00", "0", "2", "4", "6", "8", "10", "12", "14", "16"],
            "US Shoe": ["5", "5.5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10", "10.5", "11", "11.5", "12", "12.5", "13"],
            "One Size": ["One Size"]
        ]
        
        // Create any missing size combinations
        for (scale, values) in expectedSizes {
            for (idx, value) in values.enumerated() {
                let key = "\(value)|\(scale)"
                
                // If we don't have a size for this combination, create one
                if valueToKeptSize[key] == nil {
                    let existingRequest: NSFetchRequest<Size> = Size.fetchRequest()
                    existingRequest.predicate = NSPredicate(format: "value == %@ AND scale == %@", value, scale)
                    existingRequest.fetchLimit = 1
                    
                    if try context.fetch(existingRequest).isEmpty {
                        let s = Size(context: context)
                        s.id = UUID()
                        s.value = value
                        s.scale = scale
                        s.sortOrder = Int16(idx)
                        s.category = nil
                    }
                } else if let keptSize = valueToKeptSize[key] {
                    // Update sortOrder if it's not correct
                    keptSize.sortOrder = Int16(idx)
                }
            }
        }
        
        try context.save()
        print("✅ Size deduplication migration completed. Deleted \(sizesToDelete.count) duplicate sizes.")
    }
    */

    
    // MARK: - Size Helpers
    
    private func countSizes(in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Size"))
    }
    
    private func insertDefaultSizes(in context: NSManagedObjectContext) throws {
        // Define all unique scale types and their values globally
        // This ensures one Size entity per (value, scale) combination
        let globalSizeDefinitions: [String: [String]] = [
            "Alpha (XXS-XXL)": ["XXS", "XS", "S", "M", "L", "XL", "XXL"],
            "US Numeric": ["00", "0", "2", "4", "6", "8", "10", "12", "14", "16"],
            "US Shoe": ["5", "5.5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10", "10.5", "11", "11.5", "12", "12.5", "13"],
            "One Size": ["One Size"]
        ]
        
        // Create one Size per (value, scale) combination
        // Each scale type maintains its correct sort order
        for (scale, values) in globalSizeDefinitions {
            for (idx, value) in values.enumerated() {
                // Check if this size already exists (by value and scale)
                let existingRequest: NSFetchRequest<Size> = Size.fetchRequest()
                existingRequest.predicate = NSPredicate(format: "value == %@ AND scale == %@", value, scale)
                existingRequest.fetchLimit = 1
                
                if try context.fetch(existingRequest).isEmpty {
                    // Only create if it doesn't exist
                    let s = Size(context: context)
                    s.id = UUID()
                    s.value = value
                    s.scale = scale
                    s.sortOrder = Int16(idx) // Maintain correct order for each scale type
                    s.category = nil // Sizes are now independent of categories
                }
            }
        }
        
        try context.save()
    }
    
    // MARK: Wardrobes
    func preloadDefaultWardrobes(context: NSManagedObjectContext) {
        do {
            if try countWardrobes(in: context) == 0 {
                try insertDefaultWardrobes(in: context)
            }
            let names = try fetchAllWardrobes(in: context).compactMap { $0.name }
            print("✅ Wardrobes seeded or already present → \(names)")
        } catch {
            print("❌ Wardrobe seeding error:", error)
        }
    }
    
    private func countWardrobes(in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Wardrobe"))
    }
    
    private func insertDefaultWardrobes(in context: NSManagedObjectContext) throws {
        let defaults: [(String, String)] = [
            //("Closet", "closet"),
            ("Wishlist", "wishlist")
        ]
        
        for (name, type) in defaults {
            // Check if a wardrobe with this type already exists to prevent duplicates
            let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            request.predicate = NSPredicate(format: "type == %@", type)
            request.fetchLimit = 1
            
            if try context.fetch(request).isEmpty {
                // Only create if it doesn't exist
                let wardrobe = Wardrobe(context: context)
                wardrobe.id = UUID()
                wardrobe.name = name
                wardrobe.type = type
                wardrobe.isDefault = true
                let now = Date()
                wardrobe.timestamp = now
                wardrobe.createdAt = now
            }
        }
        try context.save()
    }
    
    private func fetchAllWardrobes(in context: NSManagedObjectContext) throws -> [Wardrobe] {
        try context.fetch(NSFetchRequest<Wardrobe>(entityName: "Wardrobe"))
    }
}
