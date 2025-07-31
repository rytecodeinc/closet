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
    @State private var isSettingsPresented = false

    var body: some View {
        VStack {
            Button(action: { isSettingsPresented = true }) {
                HStack {
                    Text("Settings").foregroundColor(.black)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.gray)
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
        }
    }
}
