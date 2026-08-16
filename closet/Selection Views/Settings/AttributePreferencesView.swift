//
//  AttributePreferencesView.swift
//  closet
//

import SwiftUI

struct AttributePreferencesView: View {
    @Binding var navigationPath: NavigationPath

    var body: some View {
        List {
            Button {
                navigationPath.append(ProfileRoute.categoryVisibility)
            } label: {
                attributePreferencesRow("Categories")
            }
            Button {
                navigationPath.append(ProfileRoute.colorVisibility)
            } label: {
                attributePreferencesRow("Colors")
            }
            Button {
                navigationPath.append(ProfileRoute.seasonVisibility)
            } label: {
                attributePreferencesRow("Seasons")
            }
        }
        .navigationTitle("Attribute Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func attributePreferencesRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
    }
}
