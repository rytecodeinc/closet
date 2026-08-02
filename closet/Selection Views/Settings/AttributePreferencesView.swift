//
//  AttributePreferencesView.swift
//  closet
//

import SwiftUI

struct AttributePreferencesView: View {
    var body: some View {
        List {
            NavigationLink(destination: CategoryVisibilityView()) {
                Text("Categories")
            }
            NavigationLink(destination: ColorVisibilityView()) {
                Text("Colors")
            }
            NavigationLink(destination: SeasonVisibilityView()) {
                Text("Seasons")
            }
        }
        .navigationTitle("Attribute Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }
}
