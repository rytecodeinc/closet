//
//  SizeFilterListView.swift
//  closet
//
//  Size picker for ItemFilterView.
//  Keeps filter behavior identical (binds `selectedSizeValue` only) while adding
//  the segmented size-type picker above the list (Alpha / Numeric / Shoe).
//

import SwiftUI
import CoreData

struct SizeFilterListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedSizeValue: String?
    /// When set, only sizes owned by or used by this user's items appear.
    var userId: String? = nil
    /// When true (ItemFilterView), only sizes on the user's items appear.
    var itemsOnly: Bool = false
    /// When non-empty, only sizes on items in all of these wardrobes (AND) appear.
    var wardrobes: [Wardrobe] = []
    /// `"closet"` or `"wishlist"` — controls the empty-state copy in filter mode.
    var wardrobeType: String = "closet"

    @State private var sizes: [Size] = []

    private var emptySizesMessage: String {
        wardrobeType == "wishlist"
            ? "Sizes added to your wishlist will appear here."
            : "Sizes added to your closet will appear here."
    }
    @State private var selectedSizeType: SizeType = .alpha

    var body: some View {
        VStack(spacing: 0) {
            Picker("Size Type", selection: $selectedSizeType) {
                ForEach(SizeType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                sizeNotSetRow

                if filteredSizeValues().isEmpty {
                    Text(emptySizesMessage)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(filteredSizeValues(), id: \.self) { sizeValue in
                        Button {
                            if selectedSizeValue == sizeValue {
                                selectedSizeValue = nil
                            } else {
                                selectedSizeValue = sizeValue
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
        }
        .navigationTitle("Select Size")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchSizes()
            setInitialSizeType()
        }
    }

    private var isSizeNotSetSelected: Bool {
        selectedSizeValue == ItemFilterModel.sizeNotSetFilterValue
    }

    private var sizeNotSetRow: some View {
        HStack {
            Text("None")
                .foregroundColor(.black)

            Spacer()

            if isSizeNotSetSelected {
                Image(systemName: "checkmark").foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSizeValue = ItemFilterModel.sizeNotSetFilterValue
        }
    }

    private func fetchSizes() {
        do {
            sizes = try viewContext.fetchSizesForFilterList(userId: userId, itemsOnly: itemsOnly, wardrobes: wardrobes)
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
        guard let value = selectedSizeValue, !value.isEmpty,
              value != ItemFilterModel.sizeNotSetFilterValue else { return }
        if let matching = sizes.first(where: { $0.value == value }),
           let scale = matching.scale {
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
