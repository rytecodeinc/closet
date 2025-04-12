//
//  closetApp.swift
//  closet
//
//  Created by Dan Warner on 4/12/25.
//

import SwiftUI

@main
struct closetApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
