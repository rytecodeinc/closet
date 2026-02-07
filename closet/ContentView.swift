//
//  ContentView.swift
//  closet
//
//  Created by Dan Warner on 4/12/25.
//

import SwiftUI
import CoreData

// Navigation destination identifier for ItemAddView
enum NavigationDestination: Hashable {
    case itemAdd(url: URL?, hasImage: Bool) // Use boolean flag since UIImage isn't Hashable
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Item>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.timestamp, ascending: true)],
        predicate: NSPredicate(format: "type == %@", "closet")
    ) private var closets: FetchedResults<Wardrobe>
    
    @State private var navigationPath = NavigationPath()
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TabView() {
                ClosetView()
                    .tabItem {
                        Image(systemName: "hanger")
                        Text("Closet")
                    }
                FittingView()
                    .tabItem {
                        Label("Fitting", systemImage: "tshirt")
                    }
              /*  VirtualFittingView()
                        .tabItem {
                            Label("Fitting", systemImage: "tshirt")
                        } */
              /*  OutfitGridView()
                    .tabItem {
                        Image(systemName: "book")
                        //    .environment(\.symbolVariants, .none)
                        Text("Outfits")
                    }*/
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
                migratePhotoTypes(context: viewContext)
                migrateWishlistItems(context: viewContext)
                deduplicateWardrobes(context: viewContext)
                compressExistingPhotos(context: viewContext)
                resolveSizeConstraintConflicts(context: viewContext)
                
                // Mark as appeared and check for pending navigation intent
                hasAppeared = true
                
                // Check immediately and also after a delay to handle both cases:
                // 1. Intent set before view appeared (cold start)
                // 2. Intent set after view appeared (app already running)
                checkForPendingNavigation()
                
                // Also set up a periodic check for the first few seconds
                Task { @MainActor in
                    for _ in 0..<10 { // Check 10 times over 1 second
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        if deepLinkRouter.navigationIntent != nil {
                            checkForPendingNavigation()
                            break
                        }
                    }
                }
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .itemAdd(let url, let hasImage):
                    ItemAddView(
                        parentContext: viewContext,
                        selectedWardrobe: closets.first,
                        initialURL: url,
                        initialImage: hasImage ? deepLinkRouter.navigationIntent?.image : nil
                    )
                    .onDisappear {
                        deepLinkRouter.clearIntent()
                    }
                }
            }
            .onChange(of: deepLinkRouter.navigationIntent) { intent in
                // Respond to navigation intent changes
                if let intent = intent, hasAppeared {
                    print("📱 ContentView: Navigation intent changed, navigating...")
                    navigateToItemAdd(intent: intent)
                }
            }
        }
    }
    
    /// Checks for pending navigation intent and navigates if needed
    private func checkForPendingNavigation() {
        if let intent = deepLinkRouter.navigationIntent {
            print("📱 ContentView: Found pending navigation intent on appear")
            // Small delay to ensure view hierarchy is ready
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                navigateToItemAdd(intent: intent)
            }
        }
    }
    
    /// Navigates to ItemAddView based on navigation intent
    private func navigateToItemAdd(intent: NavigationIntent) {
        guard case .addItem(let image, let url) = intent else { return }
        
        let hasImage = image != nil
        print("📱 ContentView: Navigating to ItemAddView - URL: \(url?.absoluteString ?? "nil"), hasImage: \(hasImage)")
        
        navigationPath.append(NavigationDestination.itemAdd(url: url, hasImage: hasImage))
        // Don't clear intent here - let onDisappear handle it
    }
}


#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
