//
//  FilterView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import Foundation

struct ItemFilterView: View {
    @ObservedObject var filterModel: ItemFilterModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
                List {
                    // Color filter
                    NavigationLink(destination: ColorListView(selectedColorNames: $filterModel.selectedColors)) {
                        HStack {
                            Text("Colors")
                            Spacer()
                            if !filterModel.selectedColors.isEmpty {
                                Text(filterModel.selectedColors.sorted().joined(separator: ", "))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    // Season filter
                    NavigationLink(destination: SeasonListView(selectedSeasonNames: $filterModel.selectedSeasons)) {
                        HStack {
                            Text("Seasons")
                            Spacer()
                            if !filterModel.selectedSeasons.isEmpty {
                                Text(filterModel.selectedSeasons.sorted().joined(separator: ", "))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    // Brand filter
                    NavigationLink(destination: BrandListView(selectedBrand: $filterModel.selectedBrand)) {
                        HStack {
                            Text("Brand")
                            Spacer()
                            if let brand = filterModel.selectedBrand {
                                Text(brand.name ?? "None")
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    // Price Filter
                    HStack {
                        Text("Price")
                        Spacer()
                        HStack {
                            TextField("Min Price", value: $filterModel.minPrice, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .padding(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                                .frame(width: 100)
                            Text("—")
                                .foregroundColor(.black)
                                .frame(minWidth: 10)
                            TextField("Max Price", value: $filterModel.maxPrice, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .padding(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                                .frame(width: 100)
                            
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
               // Spacer()
                Button("Reset All") {
                    filterModel.clearAll()
                }
                .foregroundColor(Color.red)
                .navigationTitle("Filter")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                   /* ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear All") {
                            filterModel.clearAll()
                        }
                    }*/
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            dismiss()
                        }
                    }
                }
            
        }
    }
}




