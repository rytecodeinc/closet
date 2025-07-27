//
//  ItemDetailView.swift
//  closet
//
//  Created by Dan Warner on 7/19/25.
//


import SwiftUI
import UIKit

import SwiftUI

struct ItemDetailView: View {
    @ObservedObject var item: Item

    @State private var isColorDrawerPresented: Bool = false
    @State private var isSeasonDrawerPresented: Bool = false
    @State private var isBrandDrawerPresented = false
    @State private var isImageFullScreen = false
    @State private var priceString: String = ""

    private let currencySymbol = Locale.current.currencySymbol ?? "$"

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                itemImageHeader()

                List {
                    attributesSection()
                    
                }
                .listStyle(.plain)
                .onAppear {
                    loadInitialPrice()
                }
            }

            if item.isWishlist {
                moveToClosetButton()
            }
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private func attributesSection() -> some View {
        Section {
            colorRow()
            seasonRow()
            brandRow()
            priceRow()
        } header: {
            Text("ATTRIBUTES")
                .fontWeight(.semibold)
        }
    }

    private func priceRow() -> some View {
            HStack {
                Text("Price")
                    .foregroundColor(.black)

                Spacer()

                HStack(spacing: 0) {
                    Text(currencySymbol)
                        .foregroundColor(.gray)

                    TextField("0.00", text: $priceString)
                        .keyboardType(.decimalPad)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .onChange(of: priceString) { newValue in
                            updatePriceAmount(from: newValue)
                        }
                }
            }
        
    }

    // MARK: - Row Helpers

    private func colorRow() -> some View {
        Button(action: { isColorDrawerPresented = true }) {
            HStack {
                Text("Colors").foregroundColor(.black)
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
                            Text("…").foregroundColor(.gray).font(.headline)
                        }
                    }
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isColorDrawerPresented) {
            ColorSelectionView(item: item)
        }
    }

    private func seasonRow() -> some View {
        Button(action: { isSeasonDrawerPresented = true }) {
            HStack {
                Text("Seasons").foregroundColor(.black)
                Spacer()
                if let selectedSeasons = item.seasons as? Set<Season>, !selectedSeasons.isEmpty {
                    let names = selectedSeasons.compactMap { $0.name }.sorted()
                    Text(names.prefix(2).joined(separator: ", "))
                        .foregroundColor(.gray)
                    if names.count > 2 {
                        Text("…").foregroundColor(.gray).font(.headline)
                    }
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isSeasonDrawerPresented) {
            SeasonSelectionView(item: item)
        }
    }

    private func brandRow() -> some View {
        Button(action: { isBrandDrawerPresented = true }) {
            HStack {
                Text("Brand").foregroundColor(.black)
                Spacer()
                if let brand = item.brand?.name, !brand.isEmpty {
                    Text(brand).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isBrandDrawerPresented) {
            BrandSelectionView(item: item)
        }
    }

    // MARK: - Header Image

    private func itemImageHeader() -> some View {
        ZStack {
            if let imageData = item.image,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .onTapGesture { isImageFullScreen = true }
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
    }

    // MARK: - Action Button

    private func moveToClosetButton() -> some View {
        Button(action: {
            item.isWishlist = false
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

    // MARK: - Price Helpers

    private func loadInitialPrice() {
        if let amount = item.price?.amount {
            priceString = String(format: "%.2f", NSDecimalNumber(decimal: amount as Decimal).doubleValue)
        }
    }

    private func updatePriceAmount(from input: String) {
        let filtered = input.filter { "0123456789.".contains($0) }
        if let value = Decimal(string: filtered) {
            if item.price == nil {
                let price = Price(context: PersistenceController.shared.container.viewContext)
                price.currency = Locale.current.currency?.identifier ?? "USD"
                item.price = price
            }
            item.price?.amount = ((value) as NSDecimalNumber)
        }
    }
}




