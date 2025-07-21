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
    @State private var isImageFullScreen = false

    var body: some View {
        List {
            // Image Row
            if let imageData = item.image,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                    .listRowInsets(EdgeInsets()) // removes default padding
                    .listRowSeparator(.hidden)
                    .onTapGesture {
                        isImageFullScreen = true
                    }
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    /*.scaledToFit()
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width)*/
                    .foregroundColor(.gray)
                    .clipped()
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            

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
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        
    }
}

