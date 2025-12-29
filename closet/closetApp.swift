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

    init() {
        _ = Self.didPrint
            print("App init: Seeding default colors")
        

        }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
