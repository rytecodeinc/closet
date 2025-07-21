//
//  DataSeeder.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import Foundation
import CoreData

import CoreData

struct DataSeeder {
    // ✅ Define this at the top level so Swift doesn't try to re-type-check it repeatedly
    private static let defaultColorNames: [String] = [
        "White", "Black", "Beige", "Red", "Orange",
        "Yellow", "Green", "Blue", "Purple", "Pink",
        "Brown", "Gray", "Silver", "Gold"
    ]
    
    

    static func preloadDefaultColors(context: NSManagedObjectContext) {
        
        
        do {
            let count = try countColors(in: context)
            if count == 0 {
                try insertDefaultColors(in: context)
            }

            let allColors = try fetchAllColors(in: context)
            var names: [String] = []
            for color in allColors {
                if let name = color.name {
                    names.append(name)
                }
            }
            print("✅ AppColor seeded or already present. Stored colors: \(names)")

        } catch {
            print("❌ DataSeeder error: \(error)")
        }
    }

    private static func countColors(in context: NSManagedObjectContext) throws -> Int {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Color")
        return try context.count(for: fetchRequest)
    }

    private static func insertDefaultColors(in context: NSManagedObjectContext) throws {
        // 🔁 Uses the static property defined above
        for name in defaultColorNames {
            let color = AppColor(context: context)
            color.name = name
            color.isVisible = true
        }

        try context.save()
    }

    private static func fetchAllColors(in context: NSManagedObjectContext) throws -> [AppColor] {
        let request = NSFetchRequest<AppColor>(entityName: "Color")
        return try context.fetch(request)
    }
}

