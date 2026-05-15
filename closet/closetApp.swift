//
//  closetApp.swift
//  closet
//
//  Created by Dan Warner on 4/12/25.
//
import Foundation
import SwiftUI
import CoreData

@main
struct closetApp: App {
    static let didPrint = {
            print("Static property initialized")
            return true
        }()
    
    let persistenceController = PersistenceController.shared
    // Use @StateObject to ensure SwiftUI observes changes to the singleton
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared
    @StateObject private var userService = UserService.shared
    // Supabase service - initializes client and loads existing session on app startup
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var authSession = AuthSession()
    @StateObject private var syncService = SyncService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var bulkItemImportCoordinator = BulkItemImportCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @State private var launchBootstrapComplete = false
    
    init() {
        _ = Self.didPrint
        print("App init: Seeding default colors")
        // ✅ Set Core Data context for sync service IMMEDIATELY
        // This ensures context is available before any views appear
        SyncService.shared.setContext(persistenceController.container.viewContext)
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if !launchBootstrapComplete {
                    LaunchView(
                        persistence: persistenceController,
                        launchBootstrapComplete: $launchBootstrapComplete
                    )
                } else if authSession.isAuthenticated {
                    ContentView()
                } else {
                    AuthView()
                }
            }
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(deepLinkRouter)
                .environmentObject(userService)
                .environmentObject(supabaseService)
                .environmentObject(authSession)
                .environmentObject(syncService)
                .environmentObject(networkMonitor)
                .environmentObject(bulkItemImportCoordinator)
                .onChange(of: scenePhase) { phase in
                    // On foreground/activation, purge any tombstones that have already been deleted in Supabase.
                    if phase == .active {
                        syncService.schedulePurgeLocalTombstones(delayNanoseconds: 1_200_000_000)
                    }
                }
                .onChange(of: networkMonitor.isConnected) { isConnected in
                    // Auto-sync when connection is restored (if user is authenticated)
                    if isConnected && authSession.isAuthenticated {
                        Task {
                            print("🌐 Network connection restored, triggering sync...")
                            do {
                                try await syncService.syncAllItems()
                                print("✅ Auto-sync completed after network restoration")
                            } catch {
                                print("⚠️ Auto-sync failed after network restoration: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                .onOpenURL { url in
                    deepLinkRouter.handleURL(url)
                }
        }
    }
}
