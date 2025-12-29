//
//  ItemGridView.swift
//  closet
//
//  Created by Dan Warner on 7/30/25.
//


import SwiftUI
import UIKit
import CoreData

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        NavigationView {
            List {
                NavigationLink("Settings") {
                    SettingsView()
                }
                NavigationLink("Size Reference") {
                    WhatSizeView()
                        .environment(\.managedObjectContext, viewContext)
                }
                
            }
            .listStyle(.plain)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        
    }
}
