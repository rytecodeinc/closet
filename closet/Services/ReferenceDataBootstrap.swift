//
//  ReferenceDataBootstrap.swift
//  closet
//
//  Seeds per-user reference data (categories, colors, seasons, sizes, etc.) matching DataSeeder
//  defaults, scoped with userId so new accounts do not see other users' attribute libraries.
//

import CoreData
import Foundation

enum ReferenceDataBootstrap {

    /// Summary counts after merging missing catalog rows for an existing account (same canonical lists as `DataSeeder`).
    struct MergeResult: Sendable {
        var colorsInserted: Int = 0
        var seasonsInserted: Int = 0
        var categoriesInserted: Int = 0
        var subcategoriesInserted: Int = 0
        var sizesInserted: Int = 0

        var totalInserted: Int {
            colorsInserted + seasonsInserted + categoriesInserted + subcategoriesInserted + sizesInserted
        }

        var isEmpty: Bool { totalInserted == 0 }
    }

    /// Adds any default colors, seasons, categories, subcategories, and sizes that this user does not already have (scoped by `userId`).
    /// Safe to run multiple times; only missing rows are created.
    static func mergeMissingDefaults(for userId: UUID, in context: NSManagedObjectContext) throws -> MergeResult {
        let uid = userId.uuidString
        var result = MergeResult()

        result.colorsInserted = try mergeMissingColors(uid: uid, in: context)
        result.seasonsInserted = try mergeMissingSeasons(uid: uid, in: context)
        let catSub = try mergeCategoriesAndSubcategories(uid: uid, in: context)
        result.categoriesInserted = catSub.categories
        result.subcategoriesInserted = catSub.subcategories
        result.sizesInserted = try mergeMissingSizes(uid: uid, in: context)

        if context.hasChanges {
            try context.save()
        }
        return result
    }

    /// Mirrors `DataSeeder` defaults; safe to call repeatedly — runs only for accounts that still need a personal catalog.
    static func ensureUserDefaults(for userId: UUID, in context: NSManagedObjectContext) throws {
        let uid = userId.uuidString

        let catProbe: NSFetchRequest<Category> = Category.fetchRequest()
        catProbe.predicate = NSPredicate(format: "userId == %@", uid)
        if try context.count(for: catProbe) > 0 {
            return
        }

        let itemProbe: NSFetchRequest<Item> = Item.fetchRequest()
        itemProbe.predicate = NSPredicate(
            format: "userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            uid
        )
        if try context.count(for: itemProbe) > 0 {
            return
        }

        try insertColors(uid: uid, in: context)
        try insertSeasons(uid: uid, in: context)
        try insertCategoriesAndSubcategories(uid: uid, in: context)
        try insertSizes(uid: uid, in: context)
        try insertDefaultBrand(uid: uid, in: context)
        try insertDefaultLocation(uid: uid, in: context)

        try context.save()
    }

    // MARK: - Constants (aligned with DataSeeder)

    private static let defaultColorNames: [String] = [
        "White", "Black", "Beige", "Red", "Orange",
        "Yellow", "Green", "Blue", "Purple", "Pink",
        "Brown", "Gray", "Silver", "Gold",
    ]

    private static let defaultSeasonNames: [String] = [
        "Spring", "Summer", "Fall", "Winter",
    ]

    private static let defaultCategoryNames: [String] = [
        "Tops", "Bottoms", "Outerwear", "Shoes", "Accessories",
        "Dresses", "Suits", "Swimwear", "Activewear",
    ]

    private static let defaultSubcategoriesByCategory: [String: [String]] = [
        "Tops": ["T-Shirts", "Blouses", "Sweaters", "Tanks"],
        "Bottoms": ["Jeans", "Trousers", "Skirts", "Shorts"],
        "Outerwear": ["Jackets", "Coats", "Blazers"],
        "Dresses": ["Mini", "Midi", "Maxi"],
        "Suits": ["Skirt Suits", "Pant Suits"],
        "Swimwear": ["One-Piece", "Bikini", "Cover-ups"],
        "Activewear": ["Leggings", "Sports Bras", "Tops"],
        "Shoes": ["Heels", "Flats", "Sneakers", "Boots", "Sandals"],
        "Accessories": ["Bags", "Belts", "Hats", "Scarves", "Jewelry"],
    ]

    private static let globalSizeDefinitions: [String: [String]] = [
        "Alpha (XXS-XXL)": ["XXS", "XS", "S", "M", "L", "XL", "XXL"],
        "US Numeric": ["00", "0", "2", "4", "6", "8", "10", "12", "14", "16"],
        "US Shoe": ["5", "5.5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10", "10.5", "11", "11.5", "12", "12.5", "13"],
        "One Size": ["One Size"],
    ]

    // MARK: - Insert helpers

    private static func mergeMissingColors(uid: String, in context: NSManagedObjectContext) throws -> Int {
        var n = 0
        for name in defaultColorNames {
            guard !colorExists(name: name, userId: uid, in: context) else { continue }
            let color = AppColor(context: context)
            color.id = UUID()
            color.name = name
            color.isVisible = true
            color.userId = uid
            n += 1
        }
        return n
    }

    private static func insertColors(uid: String, in context: NSManagedObjectContext) throws {
        _ = try mergeMissingColors(uid: uid, in: context)
    }

    private static func colorExists(name: String, userId uid: String, in context: NSManagedObjectContext) -> Bool {
        let r: NSFetchRequest<AppColor> = AppColor.fetchRequest()
        r.fetchLimit = 1
        r.predicate = NSPredicate(format: "name ==[c] %@ AND userId == %@", name, uid)
        return (try? context.count(for: r)) ?? 0 > 0
    }

    private static func mergeMissingSeasons(uid: String, in context: NSManagedObjectContext) throws -> Int {
        var n = 0
        for name in defaultSeasonNames {
            guard !seasonExists(name: name, userId: uid, in: context) else { continue }
            let season = Season(context: context)
            season.name = name
            season.id = UUID()
            season.isVisible = true
            season.userId = uid
            n += 1
        }
        return n
    }

    private static func insertSeasons(uid: String, in context: NSManagedObjectContext) throws {
        _ = try mergeMissingSeasons(uid: uid, in: context)
    }

    private static func seasonExists(name: String, userId uid: String, in context: NSManagedObjectContext) -> Bool {
        let r: NSFetchRequest<Season> = Season.fetchRequest()
        r.fetchLimit = 1
        r.predicate = NSPredicate(format: "name ==[c] %@ AND userId == %@", name, uid)
        return (try? context.count(for: r)) ?? 0 > 0
    }

    /// Full insert for brand-new accounts (no existing user categories).
    private static func insertCategoriesAndSubcategories(uid: String, in context: NSManagedObjectContext) throws {
        _ = try mergeCategoriesAndSubcategories(uid: uid, in: context)
    }

    /// Creates missing default categories and subcategories; reuses existing user-scoped categories by name.
    private static func mergeCategoriesAndSubcategories(uid: String, in context: NSManagedObjectContext) throws -> (categories: Int, subcategories: Int) {
        var categoriesInserted = 0
        var subcategoriesInserted = 0
        var byName: [String: Category] = [:]

        for name in defaultCategoryNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let existing = try fetchUserCategory(named: trimmed, userId: uid, in: context) {
                byName[trimmed.lowercased()] = existing
            } else {
                let category = Category(context: context)
                category.name = trimmed
                category.id = UUID()
                category.userId = uid
                byName[trimmed.lowercased()] = category
                categoriesInserted += 1
            }
        }

        var missing: [String] = []
        for (rawCatName, names) in defaultSubcategoriesByCategory {
            let key = rawCatName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let category = byName[key] else {
                missing.append(rawCatName)
                continue
            }
            for (idx, rawName) in names.enumerated() {
                let subName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard existingSubcategory(named: subName, in: category, userId: uid, context: context) == nil else { continue }
                let sub = Subcategory(context: context)
                sub.id = UUID()
                sub.name = subName
                sub.sortOrder = Int16(idx)
                sub.category = category
                sub.userId = uid
                subcategoriesInserted += 1
            }
        }
        if !missing.isEmpty {
            print("⚠️ ReferenceDataBootstrap: missing categories for subcategories: \(missing)")
        }
        return (categoriesInserted, subcategoriesInserted)
    }

    private static func fetchUserCategory(named name: String, userId uid: String, in context: NSManagedObjectContext) throws -> Category? {
        let r: NSFetchRequest<Category> = Category.fetchRequest()
        r.fetchLimit = 1
        r.predicate = NSPredicate(format: "userId == %@ AND name ==[c] %@", uid, name)
        return try context.fetch(r).first
    }

    private static func existingSubcategory(
        named name: String,
        in category: Category,
        userId uid: String,
        context: NSManagedObjectContext
    ) -> Subcategory? {
        let req: NSFetchRequest<Subcategory> = Subcategory.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "name ==[c] %@ AND category == %@ AND userId == %@", name, category, uid)
        return try? context.fetch(req).first
    }

    private static func mergeMissingSizes(uid: String, in context: NSManagedObjectContext) throws -> Int {
        var inserted = 0
        for (scale, values) in globalSizeDefinitions {
            for (idx, value) in values.enumerated() {
                let r: NSFetchRequest<Size> = Size.fetchRequest()
                r.fetchLimit = 1
                r.predicate = NSPredicate(format: "value == %@ AND scale == %@ AND userId == %@", value, scale, uid)
                if let existing = try context.fetch(r).first {
                    existing.sortOrder = Int16(idx)
                    continue
                }
                let s = Size(context: context)
                s.id = UUID()
                s.value = value
                s.scale = scale
                s.sortOrder = Int16(idx)
                s.category = nil
                s.userId = uid
                inserted += 1
            }
        }
        return inserted
    }

    private static func insertSizes(uid: String, in context: NSManagedObjectContext) throws {
        _ = try mergeMissingSizes(uid: uid, in: context)
    }

    private static func insertDefaultBrand(uid: String, in context: NSManagedObjectContext) throws {
        let name = "Other"
        let r: NSFetchRequest<Brand> = Brand.fetchRequest()
        r.fetchLimit = 1
        r.predicate = NSPredicate(format: "name ==[c] %@ AND userId == %@", name, uid)
        if try context.fetch(r).first != nil { return }
        let b = Brand(context: context)
        b.id = UUID()
        b.name = name
        b.isVisible = true
        b.userId = uid
    }

    private static func insertDefaultLocation(uid: String, in context: NSManagedObjectContext) throws {
        let name = "Closet"
        let r: NSFetchRequest<Location> = Location.fetchRequest()
        r.fetchLimit = 1
        r.predicate = NSPredicate(format: "name ==[c] %@ AND userId == %@", name, uid)
        if try context.fetch(r).first != nil { return }
        let loc = Location(context: context)
        loc.id = UUID()
        loc.name = name
        loc.userId = uid
    }
}
