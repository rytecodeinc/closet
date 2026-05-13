//
//  BrandListView.swift
//  closet
//
//  Created by Dan Warner on 7/26/25.
//

import SwiftUI
import CoreData
import Foundation

struct BrandListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedBrand: Brand?
    /// When set, only brands referenced by this user's items appear.
    var userId: String? = nil
    
    @State private var brands: [Brand] = []

    var body: some View {
        List {
            if brands.isEmpty {
                Text("Brands added to your closet will appear here.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(brands, id: \.self) { brand in
                    let name = brand.name ?? ""
                    Button {
                        if selectedBrand == brand {
                            selectedBrand = nil // deselect
                        } else {
                            selectedBrand = brand // select
                        }
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedBrand == brand {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Brand")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchBrands()
        }
    }

    private func fetchBrands() {
        // Avoid cross-user deletes when browsing filters scoped to one account.
        if userId == nil {
            cleanupOrphanedBrands()
        }
        
        let request: NSFetchRequest<Brand> = Brand.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Brand.name, ascending: true)]
        if let uid = userId {
            let visible = NSPredicate(format: "isVisible == YES")
            let owned = NSPredicate(format: "userId == %@", uid)
            let usedByUser = NSPredicate(
                format: "SUBQUERY(items, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                uid
            )
            let scope = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [visible, scope])
        } else {
            request.predicate = NSPredicate(format: "isVisible == YES")
        }
        do {
            let allBrands = try viewContext.fetch(request)
            if userId != nil {
                brands = allBrands
            } else {
                brands = allBrands.filter { brand in
                    if let items = brand.items as? Set<Item> {
                        return !items.isEmpty
                    }
                    return false
                }
            }
        } catch {
            print("❌ Failed to fetch brands: \(error.localizedDescription)")
            brands = []
        }
    }
    
    // MARK: - Cleanup Orphaned Brands
    private func cleanupOrphanedBrands() {
        let request: NSFetchRequest<Brand> = Brand.fetchRequest()
        request.predicate = NSPredicate(format: "isVisible == YES")
        
        do {
            let allBrands = try viewContext.fetch(request)
            let orphanedBrands = allBrands.filter { brand in
                if let items = brand.items as? Set<Item> {
                    return items.isEmpty
                }
                return true // If no items relationship, consider it orphaned
            }
            
            for brand in orphanedBrands {
                viewContext.delete(brand)
            }
            
            if !orphanedBrands.isEmpty {
                try viewContext.save()
                print("✅ Cleaned up \(orphanedBrands.count) orphaned brand(s)")
            }
        } catch {
            print("❌ Failed to cleanup orphaned brands: \(error)")
        }
    }
}




