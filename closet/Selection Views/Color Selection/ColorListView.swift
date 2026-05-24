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

    @State private var colors: [AppColor] = []

    var body: some View {
            List {
                if colors.isEmpty {
                    Text("Colors added to your closet will appear here.")
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
    
    private func fetchColors() {
        do {
            colors = try viewContext.fetchColorsForFilterList(userId: userId, itemsOnly: itemsOnly)
        } catch {
            print("❌ Failed to fetch colors: \(error.localizedDescription)")
            colors = []
        }
    }
}
