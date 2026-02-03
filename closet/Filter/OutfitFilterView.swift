//
//  OutfitFilterView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import Foundation
import CoreData

struct OutfitFilterView: View {
    @ObservedObject var filterModel: OutfitFilterModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        NavigationStack {
            List {
                // Category filter
                NavigationLink(destination: OutfitCategoryFilterListView(selectedCategory: $filterModel.selectedCategory)) {
                    HStack {
                        Text("Category")
                        Spacer()
                        if let category = filterModel.selectedCategory {
                            Text(category)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Tag filter
                NavigationLink(destination: TagListView(selectedTags: $filterModel.selectedTags)) {
                    HStack {
                        Text("Tags")
                        Spacer()
                        if !filterModel.selectedTags.isEmpty {
                            Text(filterModel.selectedTags.compactMap { $0.name }.sorted().joined(separator: ", "))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .listStyle(.plain)
            Button("Reset All") {
                filterModel.clearAll()
            }
            .foregroundColor(Color.red)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        dismiss()
                    }
                }
            }
        }
    }
}

