//
//  ItemGridView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//


import SwiftUI
import UIKit
import CoreData

struct ItemGridView: View {
    @FetchRequest var closetItems: FetchedResults<Item>
    @ObservedObject var filterModel: FilterModel
    
    @State private var isSettingsPresented = false


    let gridItems = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    init(predicate: NSPredicate? = nil, filterModel: FilterModel) {
            self.filterModel = filterModel
            _closetItems = FetchRequest(
                entity: Item.entity(),
                sortDescriptors: [],
                predicate: predicate ?? NSPredicate(value: true)
            )
        }

    var body: some View {
        VStack {
            if closetItems.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridItems, spacing: 1) {
                        ForEach(closetItems, id: \.self) { item in
                            ItemView(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Closet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    isSettingsPresented = true
                }) {
                    Image(systemName: "gear")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: FilterView(filterModel: filterModel)) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
       /* .onAppear {
                    print("✅ hehe ItemGridView appeared")
                }*/
        .frame(maxHeight: .infinity)
    }
}




