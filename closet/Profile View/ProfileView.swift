//
//  ItemGridView.swift
//  closet
//
//  Created by Dan Warner on 7/30/25.
//


import SwiftUI
import UIKit
import CoreData

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        entity: Item.entity(),
        sortDescriptors: []
    ) private var allItems: FetchedResults<Item>
    
    // MARK: - Helper Functions
    
    private func itemsForWardrobeType(_ wardrobeType: String) -> [Item] {
        // Filter items that belong to wardrobes of the specified type, excluding drafts
        // Use a dictionary keyed by item ID to ensure each item is only counted once
        var uniqueItems: [UUID: Item] = [:]
        
        for item in allItems {
            // Skip drafts
            guard !item.isDraft else { continue }
            
            guard let wardrobes = item.wardrobes as? Set<Wardrobe>,
                  wardrobes.contains(where: { $0.type == wardrobeType }) else {
                continue
            }
            
            // Use item ID to ensure uniqueness (each item only counted once)
            if let itemId = item.id {
                uniqueItems[itemId] = item
            }
        }
        
        return Array(uniqueItems.values)
    }
    
    private func totalValueForWardrobeType(_ wardrobeType: String) -> Decimal {
        // Sum all items for the specified wardrobe type, treating items without prices as 0
        let items = itemsForWardrobeType(wardrobeType)
        return items.reduce(Decimal(0)) { total, item in
            guard let price = item.price,
                  let amount = price.amount else {
                return total // Items without prices contribute 0
            }
            // Convert NSDecimalNumber to Decimal
            let decimalAmount = amount as Decimal
            return total + decimalAmount
        }
    }
    
    private func formattedValueForWardrobeType(_ wardrobeType: String) -> String {
        let totalValue = totalValueForWardrobeType(wardrobeType)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: totalValue as NSDecimalNumber) ?? "$0.00"
    }
    
    // MARK: - Computed Properties
    
    private var totalClosetValue: Decimal {
        totalValueForWardrobeType("closet")
    }
    
    private var formattedTotalValue: String {
        formattedValueForWardrobeType("closet")
    }
    
    private var totalWishlistValue: Decimal {
        totalValueForWardrobeType("wishlist")
    }
    
    private var formattedWishlistValue: String {
        formattedValueForWardrobeType("wishlist")
    }

    var body: some View {
        NavigationView {
            List {
                // Profile Header Section
                HStack(spacing: 16) {
                    // Profile Image
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.gray)
                        .clipShape(Circle())
                    
                    // Name Info
                    VStack(alignment: .leading, spacing: 4) {
                        // Name
                        Text("Name")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        // Description
                        Text("Lifestyle | Vintage | Fashion")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                
                // Closet Value Row
                HStack {
                    Text("Closet")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(formattedTotalValue)
                        .foregroundColor(.gray)
                }
                
                // Wishlist Value Row
                HStack {
                    Text("Wishlist")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(formattedWishlistValue)
                        .foregroundColor(.gray)
                }
                
                // Share links
                HStack {
                    Text("Share Links")
                }
                
                // Check Photo Sizes (Debug)
                Button {
                    checkPhotoSizes(context: viewContext)
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.doc.horizontal")
                        Text("Check Photo Sizes")
                    }
                    .foregroundColor(.blue)
                }
                
                // Vacuum Database (Reclaim Space)
                Button {
                    vacuumCoreData(context: viewContext)
                } label: {
                    HStack {
                        Image(systemName: "trash.circle")
                        Text("Reclaim Database Space")
                    }
                    .foregroundColor(.orange)
                }
            }
            .listStyle(.plain)
            .navigationTitle("@username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // Action not defined yet
                    } label: {
                        Image(systemName: "bell")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // Action not defined yet
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // Action not defined yet
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        
    }
}
