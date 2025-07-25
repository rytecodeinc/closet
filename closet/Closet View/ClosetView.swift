//
//  ClosetViewTest.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI
import CoreData

struct ClosetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject var filterModel = FilterModel()

    var body: some View {
        NavigationView {
            let basePredicate = makePredicate(for: filterModel)
            let wishlistPredicate = NSPredicate(format: "isWishlist == false")
            let finalPredicate = basePredicate.map {
                NSCompoundPredicate(andPredicateWithSubpredicates: [$0, wishlistPredicate])
            } ?? wishlistPredicate

            ItemGridView(predicate: finalPredicate, filterModel: filterModel)
                .navigationTitle("Closet")
        }
    }
}

