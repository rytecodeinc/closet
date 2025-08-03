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

    @State private var isCategoryDrawerPresented = false

    @State private var isColorDrawerPresented: Bool = false
    @State private var isSeasonDrawerPresented: Bool = false
    @State private var isBrandDrawerPresented: Bool = false
    @State private var isLocationDrawerPresented: Bool = false
    @State private var priceString: String = ""
    @State private var isLinkDrawerPresented: Bool = false
    @State private var isTagDrawerPresented: Bool = false
  
    @State private var isImageFullScreen = false
    
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
        }
        .safeAreaInset(edge: .bottom) {
            if item.isWishlist {
                moveToClosetButton()
                    .background(Color(UIColor.systemBackground))
                // .shadow(radius: 5)
            }
                
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        
    }

    // MARK: - Sections

    private func attributesSection() -> some View {
        Section {
            categoryRow()
            colorRow()
            seasonRow()
            brandRow()
            priceRow()
            linkRow()
            locationRow()
            tagRow()
        } header: {
            Text("ATTRIBUTES")
                .fontWeight(.semibold)
        }
    }
    
    // MARK: - Category Row
    private func categoryRow() -> some View {
        Button(action: { isCategoryDrawerPresented = true }) {
            HStack {
                Text("Category").foregroundColor(.black)
                Spacer()
                if let category = item.category?.name, !category.isEmpty {
                    Text(category).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isCategoryDrawerPresented) {
            CategorySelectionView(item: item)
        }
    }

    
    // MARK: - Price Row
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
    
    private func linkRow() -> some View {
        let linkNamesArray = (item.links as? Set<Link>)?
            .compactMap { $0.name }
            .sorted() ?? []

        let prefixNames = linkNamesArray.prefix(2)
        let displayString = prefixNames.joined(separator: ", ")
        let hasMore = linkNamesArray.count > 2

        return Button(action: {
            isLinkDrawerPresented = true
        }) {
            HStack {
                Text(linkNamesArray.count <= 1 ? "Link" : "Links")
                    .foregroundColor(.black)
                Spacer()
                if !displayString.isEmpty {
                    HStack(spacing: 2) {
                        Text(displayString)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        if hasMore {
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
        .sheet(isPresented: $isLinkDrawerPresented) {
            LinkSelectionView(item: item)
        }
    }

    // MARK: - Location Row
    private func locationRow() -> some View {
        Button(action: { isLocationDrawerPresented = true }) {
            HStack {
                Text("Location").foregroundColor(.black)
                Spacer()
                if let location = item.location?.name, !location.isEmpty {
                    Text(location).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isLocationDrawerPresented) {
            LocationSelectionView(item: item)
        }
    }
    
    // MARK: - Tag Row
    // MARK: - Tag Row
    private func tagRow() -> some View {
        Button(action: {
            isTagDrawerPresented = true
        }) {
            HStack {
                Text("Tags")
                    .foregroundColor(.black)

                Spacer()

                if let tagSet = item.tags as? Set<Tag>, !tagSet.isEmpty {
                    let tagNames = tagSet.compactMap { $0.name }.sorted().joined(separator: ", ")
                    Text(tagNames.prefix(20))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isTagDrawerPresented) {
            TagSelectionView(item: item)
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
        SlideToConfirmButton {
                item.isWishlist = false
                item.timestamp = Date()
                // Optional: Add haptic feedback or animation here
            }
            .transition(.move(edge: .bottom))
            .padding(.horizontal)
    }

    
    struct SlideToConfirmButton: View {
        var action: () -> Void
        var labelText: String = "Swipe to Move to Closet"
        
        @State private var dragOffset: CGFloat = 0
        @State private var completed: Bool = false
        
        let thumbSize = CGSize(width: 60, height: 40)
        let trackHeight: CGFloat = 50
        
        var body: some View {
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                
                ZStack {
                    // Background track
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: trackHeight)
                    
                    // Instruction Text
                    Text(completed ? "Moved!" : labelText)
                        .foregroundColor(.blue)
                        .font(.footnote)
                        .opacity(Double(1.0 - (dragOffset / (trackWidth - thumbSize.width))))
                        .animation(.easeInOut, value: dragOffset)
                    
                    // Draggable Thumb
                    HStack {
                        ZStack {
                            Capsule()
                                .fill(Color.white)
                                .frame(width: thumbSize.width, height: thumbSize.height)
                                .shadow(radius: 2)
                            
                            Image(systemName: completed ? "checkmark" : "arrow.right")
                                .foregroundColor(.blue)
                        }
                        .offset(x: dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    if !completed {
                                        let maxOffset = trackWidth - thumbSize.width
                                        dragOffset = min(max(0, gesture.translation.width), maxOffset)
                                    }
                                }
                                .onEnded { _ in
                                    let maxOffset = trackWidth - thumbSize.width
                                    if dragOffset > maxOffset * 0.85 {
                                        // Confirmed
                                        dragOffset = maxOffset
                                        completed = true
                                        action()
                                    } else {
                                        // Reset
                                        dragOffset = 0
                                    }
                                }
                        )
                        
                        Spacer()
                    }
                }
            }
            .frame(height: trackHeight)
            .padding(.horizontal)
        }
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




