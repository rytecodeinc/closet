//
//  ContentView.swift
//  closet
//
//  Created by Dan Warner on 4/12/25.
//

import SwiftUI
import CoreData

private enum MainTab: Hashable {
    case closet
    case fitting
    case wishlist
    case calendar
    case profile
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var authSession: AuthSession
    @EnvironmentObject var syncService: SyncService
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
    @State private var showCategoryOnboarding = false
    @State private var pendingOnboardingCategoryNames: Set<String> = Set(ReferenceDataBootstrap.masterCategoryNames)
    @State private var categoryOnboardingError: String?
    @State private var selectedTab: MainTab = .closet
    @State private var showHowToOnboarding = false
    
    // Signed-in account id (mirrors `ItemFilterView` / `AuthSession`).
    private var currentUserId: String? {
        authSession.userId?.uuidString
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
        TabView(selection: $selectedTab) {
            ClosetView()
            .tag(MainTab.closet)
            .tabItem {
                Image(systemName: "hanger")
                Text("Closet")
            }
            if appCapabilities.showsFittingTab {
                NavigationStack {
                    FittingView()
                }
                .tag(MainTab.fitting)
                .tabItem {
                    Label("Fitting", systemImage: "tshirt")
                }
            }
            if appCapabilities.showsWishlistTab {
                WishlistView()
                .tag(MainTab.wishlist)
                .tabItem {
                    Image(systemName: "heart")
                    Text("Wishlist")
                }
            }
            CalendarView()
            .tag(MainTab.calendar)
            .tabItem {
                Image(systemName: "calendar")
                Text("Calendar")
            }
            ProfileView()
            .tag(MainTab.profile)
            .tabItem {
                if appCapabilities.tier == .testflight {
                    Image(systemName: "info.circle")
                    Text("Info")
                } else {
                    Image(systemName: "person")
                    Text("Profile")
                }
            }
        }
        // Reset any restored tab + navigation state when the signed-in account changes
        // (e.g. sign out from Settings → sign back in without quitting).
        .id(authSession.userId)
        .onChange(of: authSession.userId) { _ in
            selectedTab = .closet
            deepLinkRouter.clearIntent()
            deepLinkRouter.consumeOpenNotifications()
            showDeepLinkItemAdd = false
        }
        .onChange(of: deepLinkRouter.shouldOpenNotifications) { _, open in
            guard open else { return }
            selectedTab = .profile
        }
        .task(id: authSession.userId) {
            guard let userId = authSession.userId else { return }
            PushNotificationService.shared.requestAuthorizationAndRegisterIfNeeded()
            await PushNotificationService.shared.syncStoredTokenIfNeeded()
            do {
                CategoryOnboardingStore.markCompletedIfLegacyUserHasCategories(userId: userId, in: viewContext)
                try WardrobeBootstrap.ensureDefaultWardrobes(for: userId, in: viewContext)
                try ReferenceDataBootstrap.ensureUniversalDefaults(for: userId, in: viewContext)
                if !CategoryOnboardingStore.hasCompleted(userId: userId) {
                    if appCapabilities.requiresCategoryOnboarding {
                        pendingOnboardingCategoryNames = Set(ReferenceDataBootstrap.masterCategoryNames)
                        showCategoryOnboarding = true
                    } else {
                        try CategoryOnboardingView.completeOnboardingWithFullCatalog(
                            userId: userId,
                            in: viewContext
                        )
                    }
                }
                presentHowToOnboardingIfNeeded(userId: userId)
            } catch {
                print("⚠️ WardrobeBootstrap / ReferenceDataBootstrap: \(error.localizedDescription)")
            }

            // Cold-start / returning session: wardrobe bootstrap alone is not enough for friends
            // to see items — push unsynced Closet contents (and claim legacy nil-userId rows).
            if appCapabilities.enablesCloudSync {
                do {
                    try await syncService.syncAllItems()
                    print("✅ Sync completed after session bootstrap")
                } catch {
                    print("⚠️ Sync failed after session bootstrap: \(error.localizedDescription)")
                }
            }
        }
        .fullScreenCover(isPresented: $showHowToOnboarding) {
            HowToOnboardingView {
                showHowToOnboarding = false
                selectedTab = .closet
            }
        }
        .sheet(isPresented: Binding(
            get: { appCapabilities.requiresCategoryOnboarding && showCategoryOnboarding },
            set: { showCategoryOnboarding = $0 }
        )) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        CategoryOnboardingView(
                            selectedCategoryNames: $pendingOnboardingCategoryNames,
                            onError: { categoryOnboardingError = $0 }
                        )
                        .padding(.horizontal)

                        if let categoryOnboardingError {
                            Text(categoryOnboardingError)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }

                        Button {
                            Task { await finishCategoryOnboardingFromSheet() }
                        } label: {
                            Text("Continue")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pendingOnboardingCategoryNames.isEmpty)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 16)
                }
                .navigationTitle("Your categories")
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(true)
            }
        }
        .onAppear {
                print("-- ContentView appeared")
                if deepLinkRouter.shouldOpenNotifications {
                    selectedTab = .profile
                }
                migrateOutfitCategoryStringsToEntities(context: viewContext)
                ItemLifecycleDates.migrateLifecycleDates(context: viewContext)

                // One-time migrations disabled — already completed for existing installs via UserDefaults flags.
                // migrateItemImages(context: viewContext)
                // migratePhotoTypes(context: viewContext)
                // migrateWishlistItems(context: viewContext)
                // deduplicateWardrobes(context: viewContext, userId: authSession.userId?.uuidString)
                // compressExistingPhotos(context: viewContext)
                // resolveSizeConstraintConflicts(context: viewContext)
                // migrateUserWeightFromUserDefaults(context: viewContext)
                // migrateTimestampToCreatedAt(context: viewContext)
                // migrateEventUserIdsFromRelationships(context: viewContext)
                // migrateWardrobeIsDefaultBackfill(context: viewContext)

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
                    initialImage: image,
                    sessionAccountId: authSession.userId?.uuidString
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
    
    private func finishCategoryOnboardingFromSheet() async {
        guard let userId = authSession.userId else { return }
        categoryOnboardingError = nil
        do {
            try CategoryOnboardingView.completeOnboarding(
                selectedNames: pendingOnboardingCategoryNames,
                userId: userId,
                in: viewContext
            )
            showCategoryOnboarding = false
            presentHowToOnboardingIfNeeded(userId: userId)
        } catch {
            categoryOnboardingError = error.localizedDescription
        }
    }

    /// TestFlight: first-run how-to after registration (after category sheet if any).
    private func presentHowToOnboardingIfNeeded(userId: UUID) {
        guard appCapabilities.tier == .testflight else { return }
        guard !HowToOnboardingStore.hasCompleted(userId: userId) else { return }
        guard !showCategoryOnboarding else { return }
        showHowToOnboarding = true
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
        .environment(\.appCapabilities, AppEnvironment.capabilities)
        .environmentObject(DeepLinkRouter.shared)
        .environmentObject(SupabaseService.shared)
        .environmentObject(AuthSession())
        .environmentObject(SyncService.shared)
        .environmentObject(BulkItemImportCoordinator())
}
