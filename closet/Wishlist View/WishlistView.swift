//
//  WishlistView.swift
//  closet
//
//  Created by Dan Warner on 7/24/25.
//


import SwiftUI
import CoreData

struct WishlistView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject var filterModel = FilterModel()
    
    @FetchRequest private var wishlistItems: FetchedResults<Item>
    
    init() {
        let basePredicate = makePredicate(for: FilterModel())
        let wishlistPredicate = NSPredicate(format: "isWishlist == true")
        let finalPredicate = basePredicate.map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [$0, wishlistPredicate])
        } ?? wishlistPredicate
        
        _wishlistItems = FetchRequest(
            entity: Item.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
            predicate: finalPredicate
        )
    }

    var body: some View {
        NavigationView {
            ItemGridView(filterModel: filterModel, isWishlist: true)
                .navigationTitle("Wishlist")
        }
    }
}

