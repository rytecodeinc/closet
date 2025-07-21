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
                ClosetView()
                    .tabItem {
                        Image(systemName: "book")
                        Text("Looks")
                    }
                ClosetView()
                    .tabItem {
                        Image(systemName: "heart")
                        Text("Wishlist")
                    }
                ClosetView()
                    .tabItem {
                        Image(systemName: "calendar")
                        Text("Calendar")
                    }
                ClosetView()
                    .tabItem {
                        Image(systemName: "person")
                        Text("Profile")
                    }
            }
            .onAppear {
                        print("-- ContentView appeared")
                print("App appeared")
                DataSeeder.preloadDefaultColors(context: viewContext)
                    }
        }
    }
}


#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
