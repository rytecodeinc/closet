//
//  SizeListView.swift
//  closet
//
//  Created by Dan Warner on 1/1/25.
//

import SwiftUI
import CoreData
import Foundation

struct SizeListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedSizeValue: String?
    /// When set, only sizes owned by or used by this user's items appear.
    var userId: String? = nil
    /// When true (ItemFilterView), only sizes on the user's items appear.
    var itemsOnly: Bool = false
    
    @State private var sizeValues: [String] = []

    var body: some View {
        List {
            if sizeValues.isEmpty {
                Text("Sizes added to your closet will appear here.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(sizeValues, id: \.self) { sizeValue in
                    Button {
                        if selectedSizeValue == sizeValue {
                            selectedSizeValue = nil // deselect
                        } else {
                            selectedSizeValue = sizeValue // select
                        }
                    } label: {
                        HStack {
                            Text(sizeValue)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedSizeValue == sizeValue {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Size")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchSizes()
        }
    }

    private func fetchSizes() {
        do {
            let allSizes = try viewContext.fetchSizesForFilterList(userId: userId, itemsOnly: itemsOnly)
            var seenValues = Set<String>()
            sizeValues = allSizes.compactMap { size in
                guard let value = size.value, !value.isEmpty else { return nil }
                if seenValues.contains(value) {
                    return nil
                }
                seenValues.insert(value)
                return value
            }
        } catch {
            print("❌ Failed to fetch sizes: \(error.localizedDescription)")
            sizeValues = []
        }
    }
}

