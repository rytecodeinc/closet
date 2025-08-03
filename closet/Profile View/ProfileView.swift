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

    var body: some View {
        NavigationView {
            List {
                NavigationLink("Settings") {
                    SettingsView()
                }
                
            }
            .listStyle(.plain)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        
    }
}
