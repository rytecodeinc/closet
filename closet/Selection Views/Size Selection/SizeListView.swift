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
    
    @State private var sizes: [Size] = []
    @State private var selectedSizeType: SizeType = .alpha

    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: "Select Size") {
                Picker("Size Type", selection: $selectedSizeType) {
                    ForEach(SizeType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            List {
                if filteredSizeValues().isEmpty {
                    Text("Sizes added to your closet will appear here.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(filteredSizeValues(), id: \.self) { sizeValue in
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
        }
        .listStyle(.plain)
        .onAppear {
            fetchSizes()
            setInitialSizeType()
        }
    }

    private func fetchSizes() {
        do {
            sizes = try viewContext.fetchSizesForFilterList(userId: userId, itemsOnly: itemsOnly)
        } catch {
            print("❌ Failed to fetch sizes: \(error.localizedDescription)")
            sizes = []
        }
    }

    private func filteredSizeValues() -> [String] {
        let filtered = sizes.filter { selectedSizeType.matches(scale: $0.scale) }
        // Preserve order from Core Data sort descriptors, but dedupe by display value.
        var seenValues = Set<String>()
        var result: [String] = []
        for size in filtered {
            guard let value = size.value, !value.isEmpty else { continue }
            guard !seenValues.contains(value) else { continue }
            seenValues.insert(value)
            result.append(value)
        }
        return result
    }

    private func setInitialSizeType() {
        guard let value = selectedSizeValue, !value.isEmpty else { return }
        // If the currently selected filter value exists in one of the scales, default the segmented picker to that scale.
        if let matching = sizes.first(where: { $0.value == value }), let scale = matching.scale {
            if SizeType.alpha.matches(scale: scale) {
                selectedSizeType = .alpha
            } else if SizeType.numeric.matches(scale: scale) {
                selectedSizeType = .numeric
            } else if SizeType.shoe.matches(scale: scale) {
                selectedSizeType = .shoe
            }
        }
    }
}

