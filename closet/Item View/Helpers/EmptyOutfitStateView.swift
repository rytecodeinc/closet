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
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tshirt")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No saved outfits yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Outfits are collages of items from your closet.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it takes full height
    }
}
