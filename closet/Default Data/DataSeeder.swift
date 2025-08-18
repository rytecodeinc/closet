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
        preloadDefaultSizes(context: context)
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
          //  category.isVisible = true
        }
        try context.save()
    }

    private func fetchAllCategories(in context: NSManagedObjectContext) throws -> [Category] {
        try context.fetch(NSFetchRequest<Category>(entityName: "Category"))
    }
    
    // Public entry point (match your other preloaders)
    func preloadDefaultSizes(context: NSManagedObjectContext, forceReseed: Bool = false) {
        do {
            if forceReseed {
                try deleteAllSizes(in: context)
            }
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

    
    // MARK: - Size Helpers
    
    private func countSizes(in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Size"))
    }
    
    private func insertDefaultSizes(in context: NSManagedObjectContext) throws {
        let categories = try fetchAllCategories(in: context)
        let byName = Dictionary(uniqueKeysWithValues: categories.compactMap { cat in
            (cat.name.map { ($0, cat) })
        })

        for (catName, bundles) in Self.defaultSizesByCategory {
            guard let cat = byName[catName] else { continue }

            // Keep values in each bundle contiguous and ordered
            var runningOrder: Int16 = 0
            for bundle in bundles {
                for (idx, v) in bundle.values.enumerated() {
                    let s = Size(context: context)
                    s.id = UUID()
                    s.value = v
                    s.scale = bundle.scale
                    s.sortOrder = runningOrder // or Int16(idx) if you don’t care about bundle grouping
                    s.category = cat
                    runningOrder += 1
                }
            }
        }
        try context.save()
    }
    
}
