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
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var bulkItemImportCoordinator: BulkItemImportCoordinator

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.createdAt, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
        animation: .default)
    private var allItems: FetchedResults<Item>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)],
        predicate: NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", "closet")
    ) private var allClosets: FetchedResults<Wardrobe>
    
    @State private var hasAppeared = false
    @State private var showDeepLinkItemAdd = false
    
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
        TabView() {
            NavigationStack {
                ClosetView()
            }
            .tabItem {
                Image(systemName: "hanger")
                Text("Closet")
            }
            NavigationStack {
                FittingView()
            }
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
            NavigationStack {
                WishlistView()
            }
            .tabItem {
                Image(systemName: "heart")
                Text("Wishlist")
            }
            NavigationStack {
                OutfitCalendarView()
            }
            .tabItem {
                Image(systemName: "calendar")
                Text("Calendar")
            }
            NavigationStack {
                ProfileView()
            }
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
                deduplicateWardrobes(context: viewContext, userId: SupabaseService.shared.currentUser?.id.uuidString)
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
        .fullScreenCover(isPresented: $showDeepLinkItemAdd) {
            if let intent = deepLinkRouter.navigationIntent, case .addItem(let image, let url) = intent {
                ItemAddView(
                    parentContext: viewContext,
                    selectedWardrobe: closets.first,
                    initialURL: url,
                    initialImage: image
                )
                .environmentObject(bulkItemImportCoordinator)
                .onDisappear {
                    deepLinkRouter.clearIntent()
                    showDeepLinkItemAdd = false
                }
            }
        }
        .onChange(of: deepLinkRouter.navigationIntent) { intent in
            // Respond to navigation intent changes — present ItemAddView for add-item deep links
            if let intent = intent, hasAppeared, case .addItem = intent {
                print("📱 ContentView: Navigation intent changed, presenting ItemAddView")
                navigateToItemAdd(intent: intent)
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
    
    /// Presents ItemAddView for add-item deep links (via fullScreenCover)
    private func navigateToItemAdd(intent: NavigationIntent) {
        guard case .addItem = intent else { return }
        
        print("📱 ContentView: Presenting ItemAddView for deep link")
        showDeepLinkItemAdd = true
    }
}


#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(BulkItemImportCoordinator())
}
