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
    @EnvironmentObject var supabaseService: SupabaseService

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.createdAt, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
        animation: .default)
    private var allItems: FetchedResults<Item>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)],
        predicate: NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", "closet")
    ) private var allClosets: FetchedResults<Wardrobe>
    
    @State private var navigationPath = NavigationPath()
    @State private var hasAppeared = false
    
    // Computed property for current user ID
    private var currentUserId: String? {
        supabaseService.currentUser?.id.uuidString
    }
    
    // Filter items by userId (since @FetchRequest can't use dynamic predicates)
    private var items: [Item] {
        guard let userId = currentUserId else { return [] }
        return allItems.filter { $0.userId == userId }
    }
    
    // Filter closets by userId
    private var closets: [Wardrobe] {
        guard let userId = currentUserId else { return [] }
        return allClosets.filter { $0.userId == userId }
    }

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
                LoginView()
                    .tabItem {
                        Image(systemName: "lock")
                        Text("Login")
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
                migrateUserWeightFromUserDefaults(context: viewContext)
                migrateTimestampToCreatedAt(context: viewContext)
                
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
