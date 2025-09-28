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
    
    @FetchRequest private var closetItems: FetchedResults<Item>
    
    init() {
        let basePredicate = makePredicate(for: FilterModel())
        let closetPredicate = NSPredicate(format: "ANY collections.type == %@", "wishlist")
        let finalPredicate = basePredicate.map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [$0, closetPredicate])
        } ?? closetPredicate
        
        _closetItems = FetchRequest(
            entity: Item.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
            predicate: finalPredicate
        )
    }

    var body: some View {
        NavigationView {
            ItemGridView(filterModel: filterModel, collectionType: "wishlist")
                .navigationTitle("Wishlist")
        }
    }
}

