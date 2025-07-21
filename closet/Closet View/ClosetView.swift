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
            let predicate = makePredicate(for: filterModel.selectedColors)

                ItemGridView(predicate: predicate, filterModel: filterModel)
        }
    }

}
