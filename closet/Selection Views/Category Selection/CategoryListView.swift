//
//  CategoryListView.swift
//  closet
//
//  Created by Dan Warner on 8/2/25.
//


import SwiftUI
import CoreData
import Foundation

struct CategoryListView: View {
    @Binding var selectedCategoryName: String?

    @FetchRequest(
        entity: Category.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
    ) private var categories: FetchedResults<Category>

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                let name = category.name ?? ""

                HStack {
                    Text(name)
                        .foregroundColor(.black)

                    Spacer()

                    if selectedCategoryName == name {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedCategoryName == name {
                        selectedCategoryName = nil
                    } else {
                        selectedCategoryName = name
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Category")
        .navigationBarTitleDisplayMode(.inline)
    }
}
