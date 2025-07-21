//
//  EmptyStateView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//

import SwiftUI
import CoreData

struct EmptyStateView: View {
    var body: some View {
        VStack {
            Spacer() // Push the content to the center
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.gray)
            Text("No Items")
                .font(.headline)
                .foregroundColor(.gray)
            Spacer() // Keep it centered vertically
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it takes full height
    }
}
