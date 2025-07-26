//
//  BrandListView.swift
//  closet
//
//  Created by Dan Warner on 7/26/25.
//

import SwiftUI
import CoreData
import Foundation

struct BrandListView: View {
    @Binding var selectedBrand: Brand?

    @FetchRequest(
        entity: Brand.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Brand.name, ascending: true)],
        predicate: NSPredicate(format: "isVisible == YES")
    )
    private var visibleBrands: FetchedResults<Brand>

    var body: some View {
        List {
            ForEach(visibleBrands, id: \.self) { brand in
                let name = brand.name ?? ""
                Button {
                    selectedBrand = brand
                } label: {
                    HStack {
                        Text(name)
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedBrand == brand {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Brand")
        .navigationBarTitleDisplayMode(.inline)
    }
}


