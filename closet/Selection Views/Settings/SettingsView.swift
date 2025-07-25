//
//  SettingsView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI
import CoreData

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: ColorVisibilityView()) {
                    Text("Colors")
                }
                NavigationLink(destination: SeasonVisibilityView()) {
                    Text("Seasons")
                }
                // Add more categories here later (Size, etc)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


