//
//  EmptyOutfitStateView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import Foundation
import SwiftUI
import CoreData

struct EmptyOutfitStateView: View {
    var title: String = "No saved outfits yet"
    var message: String = "Click the '+' button to create an outfit"
    var systemImage: String = "tshirt"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it takes full height
    }
}
