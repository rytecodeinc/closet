//
//  ContentView.swift
//  closet
//
//  Created by Dan Warner on 4/12/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Item>

    var body: some View {
        NavigationStack {
            TabView() {
                ClosetView()
                    .tabItem {
                        Image(systemName: "hanger")
                        Text("Closet")
                    }
                OutfitGridView()
                    .tabItem {
                        Image(systemName: "book")
                        //    .environment(\.symbolVariants, .none)
                        Text("Outfits")
                    }
                WishlistView()
                    .tabItem {
                        Image(systemName: "heart")
                        Text("Wishlist")
                    }
                OutfitCalendarView()
                    .tabItem {
                        Image(systemName: "calendar")
                        Text("Calendar")
                    }
                ProfileView()
                    .tabItem {
                        Image(systemName: "person")
                        Text("Profile")
                    }
            }
            .onAppear {
                print("-- ContentView appeared")
                migrateItemImages(context: viewContext)
                migrateWishlistItems(context: viewContext)
                deduplicateWardrobes(context: viewContext)
            }
        }
    }
}


#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
