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

    init() {
        _ = Self.didPrint
            print("App init: Seeding default colors")
        

        }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(deepLinkRouter)
                .environmentObject(userService)
                .environmentObject(supabaseService)
                .onOpenURL { url in
                    deepLinkRouter.handleURL(url)
                }
        }
    }
}
