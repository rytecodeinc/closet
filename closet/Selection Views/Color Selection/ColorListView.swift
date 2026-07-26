//
//  ColorListView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import Foundation
import SwiftUI
import CoreData

struct ColorListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedColorNames: Set<String>
    /// When set, only colors owned by or used by this user's items appear.
    var userId: String? = nil
    /// When true (ItemFilterView), only colors on the user's items appear. When false (item add), the user's full color catalog is shown.
    var itemsOnly: Bool = false
    /// When non-empty, only colors on items in all of these wardrobes (AND) appear.
    var wardrobes: [Wardrobe] = []
    /// `"closet"` or `"wishlist"` — empty-state copy when `itemsOnly` is true.
    var wardrobeType: String = "closet"

    @State private var colors: [AppColor] = []

    private var emptyColorsMessage: String {
        guard itemsOnly else { return "Colors added to your closet will appear here." }
        return wardrobeType == "wishlist"
            ? "Colors added to your wishlist will appear here."
            : "Colors added to your closet will appear here."
    }

    var body: some View {
            List {
                if itemsOnly {
                    colorNotSetRow
                }

                if colors.isEmpty {
                    Text(emptyColorsMessage)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(colors, id: \.objectID) { color in
                        let name = color.name ?? ""

                        HStack {
                            Circle()
                                .fill(colorFromName(name))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.gray, lineWidth: 1))

                            Text(name)
                                .foregroundColor(.black)

                            Spacer()

                            if selectedColorNames.contains(name) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedColorNames.remove(ItemFilterModel.colorNotSetFilterValue)
                            if selectedColorNames.contains(name) {
                                selectedColorNames.remove(name)
                            } else {
                                selectedColorNames.insert(name)
                            }
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle("Select Colors")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: fetchColors)
    }

    private var isColorNotSetSelected: Bool {
        selectedColorNames.contains(ItemFilterModel.colorNotSetFilterValue)
    }

    private var colorNotSetRow: some View {
        HStack {
            Text("None")
                .foregroundColor(.black)

            Spacer()

            if isColorNotSetSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedColorNames = [ItemFilterModel.colorNotSetFilterValue]
        }
    }
    
    private func fetchColors() {
        do {
            colors = try viewContext.fetchColorsForFilterList(
                userId: userId,
                itemsOnly: itemsOnly,
                wardrobeType: itemsOnly ? wardrobeType : nil,
                wardrobes: wardrobes
            )
        } catch {
            print("❌ Failed to fetch colors: \(error.localizedDescription)")
            colors = []
        }
    }
}
