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
    
    // MARK: - Init
    
    init(context: NSManagedObjectContext) {
        preloadDefaultColors(context: context)
        preloadDefaultSeasons(context: context)
        // Add additional preloaders here (e.g., Tags, Sizes, Categories)
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
        }
        try context.save()
    }

    private func fetchAllSeasons(in context: NSManagedObjectContext) throws -> [Season] {
        try context.fetch(NSFetchRequest<Season>(entityName: "Season"))
    }
}

