//
//  FilterView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import Foundation
import CoreData

struct ItemFilterView: View {
    @ObservedObject var filterModel: ItemFilterModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession
    
    var wardrobeType: String = "closet" // Default to "closet" for backward compatibility

    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    var body: some View {
        NavigationStack {
            List {
                // Sort row
                Picker("Sort", selection: $filterModel.sortOrder) {
                    ForEach(ItemSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                
                // Favorites-only filter
                Toggle("Favorites", isOn: $filterModel.favoritesOnly)
                
                // Wardrobe filter
                NavigationLink(destination: WardrobeListView(
                    selectedWardrobes: $filterModel.selectedWardrobes,
                    defaultWardrobeType: wardrobeType,
                    userId: currentUserId
                )
                ) {
                    HStack {
                        Text("Wardrobes")
                        Spacer()
                        if !filterModel.selectedWardrobes.isEmpty {
                            Text(filterModel.selectedWardrobes.compactMap { $0.name }.sorted().joined(separator: ", "))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Category filter
                NavigationLink(destination: CategoryFilterListView(
                    selectedCategoryName: $filterModel.selectedCategoryName,
                    selectedSubcategoryName: $filterModel.selectedSubcategoryName,
                    userId: currentUserId
                )
                ) {
                    HStack {
                        Text("Category")
                        Spacer()
                        if let categoryName = filterModel.selectedCategoryName {
                            if let subcategoryName = filterModel.selectedSubcategoryName {
                                Text("\(categoryName) • \(subcategoryName)")
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            } else {
                                Text(categoryName)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                // Brand filter
                NavigationLink(destination: BrandListView(selectedBrand: $filterModel.selectedBrand, userId: currentUserId)) {
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
                
                // Size filter
                NavigationLink(destination: SizeListView(selectedSizeValue: $filterModel.selectedSizeValue, userId: currentUserId, itemsOnly: true)) {
                    HStack {
                        Text("Size")
                        Spacer()
                        if let sizeValue = filterModel.selectedSizeValue {
                            Text(sizeValue)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Color filter
                NavigationLink(destination: ColorListView(selectedColorNames: $filterModel.selectedColors, userId: currentUserId, itemsOnly: true)) {
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
                 
                /*
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
                */
                // Location filter
                NavigationLink(destination: LocationListView(selectedLocation: $filterModel.selectedLocation, userId: currentUserId)) {
                    HStack {
                        Text("Location")
                        Spacer()
                        if let location = filterModel.selectedLocation {
                            Text(location.name ?? "None")
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
                
                if appCapabilities.showsWeightAttribute {
                    HStack {
                        Text("Weight")
                            .foregroundColor(.primary)
                        Spacer()

                        if filterModel.filterByWeight {
                            let repository = UserProfileRepository(context: viewContext)
                            let userWeightKg = repository.getWeightKg()
                            let userWeightUnit = repository.getWeightUnit()

                            if userWeightKg > 0 {
                                let displayWeight = userWeightUnit == "kg" ? userWeightKg : userWeightKg * 2.20462
                                Text("\(String(format: "%.1f", displayWeight)) \(userWeightUnit)")
                                    .foregroundColor(.gray)
                                    .font(.subheadline)
                            } else {
                                Text("Set in Profile")
                                    .foregroundColor(.orange)
                                    .font(.subheadline)
                            }
                        }

                        Toggle("", isOn: $filterModel.filterByWeight)
                            .labelsHidden()
                    }
                }

                // Tag filter
                NavigationLink(destination: TagListView(selectedTags: $filterModel.selectedTags, wardrobeType: wardrobeType, userId: currentUserId)) {
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
                
                // Reset button
                Section {
                      Button("Reset All", role: .destructive) {
                          filterModel.clearAll()
                      }
                      .frame(maxWidth: .infinity, alignment: .center)
                  }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            //  .onAppear { print("ItemFilterView: onAppear") }
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
        .toolbar(.hidden, for: .tabBar)
    }
}




