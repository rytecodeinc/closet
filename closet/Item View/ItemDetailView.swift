//
//  ItemDetailView.swift
//  closet
//
//  Created by Dan Warner on 7/19/25.
//


import SwiftUI
import UIKit

struct ItemDetailView: View {
    @ObservedObject var item: Item

    @State private var isColorDrawerPresented: Bool = false
    @State private var isSeasonDrawerPresented: Bool = false
    @State private var isBrandDrawerPresented = false
    @State private var isImageFullScreen = false
    

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Fixed Image at the Top
                ZStack {
                    if let imageData = item.image,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .onTapGesture {
                                isImageFullScreen = true
                            }
                    } else {
                        Image(systemName: "photo")
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.gray)
                            .clipped()
                    }

                    if item.isWishlist {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 30))
                            .padding(10)
                            .offset(x: 160, y: -160)
                    }
                }

                // Scrollable content
                List {
                    Section {
                        // Color Row
                        Button(action: {
                            isColorDrawerPresented = true
                        }) {
                            HStack {
                                Text("Colors")
                                    .foregroundColor(.black)
                                Spacer()
                                
                                if let selectedColorsSet = item.colors as? Set<AppColor>, !selectedColorsSet.isEmpty {
                                    let sortedColors = selectedColorsSet.sorted { ($0.name ?? "") < ($1.name ?? "") }
                                    
                                    HStack(spacing: 8) {
                                        ForEach(sortedColors.prefix(4), id: \.self) { appColor in
                                            Circle()
                                                .fill(colorFromName(appColor.name ?? ""))
                                                .frame(width: 20, height: 20)
                                                .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                                        }
                                        
                                        if sortedColors.count > 4 {
                                            Text("…")
                                                .foregroundColor(.gray)
                                                .font(.headline)
                                        }
                                    }
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        .sheet(isPresented: $isColorDrawerPresented) {
                            ColorSelectionView(item: item)
                        }
                        
                        // Season Row
                        Button(action: {
                            isSeasonDrawerPresented = true
                        }) {
                            HStack {
                                Text("Seasons")
                                    .foregroundColor(.black)
                                Spacer()
                                
                                if let selectedSeasons = item.seasons as? Set<Season>, !selectedSeasons.isEmpty {
                                    let names = selectedSeasons.compactMap { $0.name }.sorted()
                                    Text(names.prefix(2).joined(separator: ", "))
                                        .foregroundColor(.gray)
                                    
                                    if names.count > 2 {
                                        Text("…")
                                            .foregroundColor(.gray)
                                            .font(.headline)
                                    }
                                }
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        .sheet(isPresented: $isSeasonDrawerPresented) {
                            SeasonSelectionView(item: item)
                        }
                        
                    }
                    header: {
                        Text("ATTRIBUTES")
                            .fontWeight(.semibold)
                     //     .foregroundStyle(.blue)
                    } // end of Section
                    
                    // Brand Row (Temporary for testing)
                    Button(action: {
                        isBrandDrawerPresented = true
                    }) {
                        HStack {
                            Text("Brand")
                                .foregroundColor(.black)
                            Spacer()
                            
                             if let brand = item.brand?.name, !brand.isEmpty {
                                 Text(brand)
                                     .foregroundColor(.gray)
                             }
/*
                            Text("Select") // Static placeholder
                                .foregroundColor(.gray)
*/
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    .sheet(isPresented: $isBrandDrawerPresented) {
                        // Dummy string binding for testing
                        BrandSelectionView(item: item)
                    }


                    // Add more rows here as needed
                }
                .listStyle(PlainListStyle())
            }

            // Sticky "Move to Closet" button
            if item.isWishlist {
                Button(action: {
                    item.isWishlist == true
                }) {
                    Label("Move to Closet", systemImage: "hanger")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding([.horizontal, .bottom])
                    
                }
                .transition(.move(edge: .bottom))
            }
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}




