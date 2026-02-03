//
//  AttributesSectionView.swift
//  closet
//
//  Created by Dan Warner on 8/16/25.
//


// MARK: - AttributesSectionView
// Single source of truth for Category, Size, Colors, Seasons, Brand, Price, Links, Location, Tags
// Works in both ItemDetailView (parent MOC) and ItemAddView (child MOC) by inheriting the ambient managedObjectContext.

import SwiftUI
import CoreData

struct AttributesSectionView: View {
    @ObservedObject var item: Item

    // One enum instead of many booleans
    @Binding var activeSheet: Sheet?

    // Currency symbol (display only)
    private let currencySymbol = Locale.current.currencySymbol ?? "$"

    var body: some View {
        Section {
            wardrobeRow()
            nameRow()
            categoryRow()
            brandRow()
            sizeRow()
            colorRow()
            seasonRow()
            locationRow()
            priceRow()
            weatherRow()
            weightRow()
            linkRow()
            tagRow()
            notesRow()
            dateAddedRow()
        }
    }
}

// MARK: - Sheet enum
extension AttributesSectionView {
    enum Sheet: String, Identifiable {
        case wardrobe, name, category, size, color, season, brand, price, link, location, tag, notes, weather, weight
        var id: String { rawValue }
    }
}

// MARK: - Rows
extension AttributesSectionView {
    func wardrobeRow() -> some View {
        Button { activeSheet = .wardrobe } label: {
            HStack {
                Text("Wardrobes")
                    .foregroundColor(.primary)
                Spacer()
                
                if let wardrobes = item.wardrobes as? Set<Wardrobe>, !wardrobes.isEmpty {
                    // Display names, e.g., "Closet • Capsule • Summer"
                    let names = wardrobes.compactMap { $0.name }.sorted()
                    Text(names.prefix(2).joined(separator: ", "))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if names.count > 2 {
                        Text("…").foregroundColor(.gray).font(.headline)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }
    
    // Name
    func nameRow() -> some View {
        Button { activeSheet = .name } label: {
            HStack {
                Text("Name").foregroundColor(.primary)
                Spacer()
                if let name = item.name, !name.isEmpty {
                    let displayText = name.count > 27 ? String(name.prefix(27)) + "…" : name
                    Text(displayText).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }
    
    // Category
    // Helper: what to show on the right side of the row
    private var categoryDisplayText: String? {
        guard let catName = item.category?.name, !catName.isEmpty else { return nil }
        if let sub = item.subcategory,
           sub.category == item.category,                  // ensure it matches the current category
           let subName = sub.name, !subName.isEmpty {
            return "\(catName) • \(subName)"
        }
        return catName
    }

    // MARK: - Category Row
    func categoryRow() -> some View {
        Button { activeSheet = .category } label: {
            HStack {
                Text("Category")
                    .foregroundColor(.primary)
                Spacer()
                if let label = categoryDisplayText {
                    Text(label)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.85)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            // Optional accessibility hint
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Category")
            .accessibilityValue(categoryDisplayText ?? "None selected")
        }
    }


    // Size (NEW unified row)
    var selectedSizeText: String? {
        guard let size = item.size, let value = size.value, !value.isEmpty else { return nil }
        return value
    }

    func sizeRow() -> some View {
        Button { activeSheet = .size } label: {
            HStack {
                Text("Size").foregroundColor(.primary)
                Spacer()
                if let label = selectedSizeText {
                    Text(label).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }

    // Colors
    func colorRow() -> some View {
        Button { activeSheet = .color } label: {
            HStack {
                Text("Colors").foregroundColor(.primary)
                Spacer()
                if let selected = item.colors as? Set<AppColor>, !selected.isEmpty {
                    let sorted = selected.sorted { ($0.name ?? "") < ($1.name ?? "") }
                    HStack(spacing: 8) {
                        ForEach(sorted.prefix(4), id: \.self) { appColor in
                            Circle()
                                .fill(colorFromName(appColor.name ?? ""))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                        }
                        if sorted.count > 4 { Text("…").foregroundColor(.gray).font(.headline) }
                    }
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }

    // Seasons
    func seasonRow() -> some View {
        Button { activeSheet = .season } label: {
            HStack {
                Text("Seasons").foregroundColor(.primary)
                Spacer()
                if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
                    let names = seasons.compactMap { $0.name }.sorted()
                    let displayText = names.count > 2 ? names.prefix(2).joined(separator: ", ") + "…" : names.joined(separator: ", ")
                    Text(displayText).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }

    // Brand
    func brandRow() -> some View {
        Button { activeSheet = .brand } label: {
            HStack {
                Text("Brand").foregroundColor(.primary)
                Spacer()
                if let brand = item.brand?.name, !brand.isEmpty {
                    Text(brand).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }

    // Price Row
    func priceRow() -> some View {
        Button { activeSheet = .price } label: {
            HStack {
                Text("Price").foregroundColor(.primary)
                Spacer()
                if let price = item.price, let amount = price.amount {
                    let currencySymbol = (price.currency != nil)
                        ? Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: price.currency!]))
                            .currencySymbol ?? "$"
                        : Locale.current.currencySymbol ?? "$"
                    
                    HStack(spacing: 2) {
                        Text(currencySymbol)
                            .foregroundColor(.gray)
                        Text(NumberFormatter.currency2.string(from: amount) ?? "0.00")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .padding(.leading, 4)
            }
        }
    }

    // Weather Row
    func weatherRow() -> some View {
        Button { activeSheet = .weather } label: {
            HStack {
                Text("Weather").foregroundColor(.primary)
                Spacer()
                // Use primitiveValue to properly handle optional scalar types
                if let minC = item.primitiveValue(forKey: "minTemperature") as? Double,
                   let maxC = item.primitiveValue(forKey: "maxTemperature") as? Double {
                    let unit = (item.primitiveValue(forKey: "temperatureUnit") as? String) ?? "C"
                    let symbol = unit == "C" ? "°C" : "°F"
                    let displayMin = unit == "C" ? Int(minC) : Int((minC * 9/5) + 32)
                    let displayMax = unit == "C" ? Int(maxC) : Int((maxC * 9/5) + 32)
                    Text("\(displayMin)° to \(displayMax)\(symbol)")
                        .foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }

    // Weight Row
    func weightRow() -> some View {
        Button { activeSheet = .weight } label: {
            HStack {
                Text("Weight").foregroundColor(.primary)
                Spacer()
                // Use primitiveValue to properly handle optional scalar types
                if let weightKg = item.primitiveValue(forKey: "weight") as? Double {
                    let unit = (item.primitiveValue(forKey: "weightUnit") as? String) ?? "kg"
                    let symbol = unit == "kg" ? "kg" : "lbs"
                    let displayWeight = unit == "kg" ? weightKg : weightKg * 2.20462
                    Text("\(String(format: "%.1f", displayWeight)) \(symbol)")
                        .foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }


    // Links
    func linkRow() -> some View {
        let names = (item.links as? Set<Link>)?.compactMap { $0.name }.sorted() ?? []
        let display = names.prefix(2).joined(separator: ", ")
        let hasMore = names.count > 2

        return Button { activeSheet = .link } label: {
            HStack {
                Text(names.count <= 1 ? "Link" : "Links").foregroundColor(.primary)
                Spacer()
                if !display.isEmpty {
                    HStack(spacing: 2) {
                        Text(display).foregroundColor(.gray).lineLimit(1)
                        if hasMore { Text("…").foregroundColor(.gray).font(.headline) }
                    }
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }

    // Location
    func locationRow() -> some View {
        Button { activeSheet = .location } label: {
            HStack {
                Text("Location").foregroundColor(.primary)
                Spacer()
                if let loc = item.location?.name, !loc.isEmpty {
                    Text(loc).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }

    // Tags
    func tagRow() -> some View {
        Button { activeSheet = .tag } label: {
            HStack {
                Text("Tags").foregroundColor(.primary)
                Spacer()
                if let tagSet = item.tags as? Set<Tag>, !tagSet.isEmpty {
                    let names = tagSet.compactMap { $0.name }.sorted().joined(separator: ", ")
                    Text(names.prefix(20))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }
    
    // Notes
    func notesRow() -> some View {
        Button { activeSheet = .notes } label: {
            HStack {
                Text("Notes").foregroundColor(.primary)
                Spacer()
                if let notes = item.notes, !notes.isEmpty {
                    let displayText = notes.count > 27 ? String(notes.prefix(27)) + "…" : notes
                    Text(displayText).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }
    
    // Date Added (non-tappable, informational only)
    func dateAddedRow() -> some View {
        HStack {
            Text("Date Added")
                .foregroundColor(.gray)
            Spacer()
            if let timestamp = item.timestamp {
                Text(timestamp, style: .date)
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Optional local formatter if you do not already have one elsewhere
extension NumberFormatter {
    static let currency2: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
}

// ==============================================================
// MARK: - Integrations
// Replace usages in ItemDetailView and ItemAddView
// ==============================================================

// In ItemDetailView: replace the Section call with the new shared view.
// Before:
//     attributesSection()
// After:
//     AttributesSectionView(item: item)

// For example, inside ItemDetailView body:
// List {
//     itemImageHeader()
//         .listRowInsets(EdgeInsets(.zero))
//     AttributesSectionView(item: item)
// }

// Remove the old attributesSection() and its per-row helpers from ItemDetailView.

// In ItemAddView: replace ItemAttributesSection(item: vm.draftItem) with:
//     AttributesSectionView(item: vm.draftItem)
// Keep your existing `.environment(\.managedObjectContext, vm.childContext)` higher up, so the section + drawers inherit the child context.

extension AttributesSectionView.Sheet {
    @ViewBuilder
    func destination(for item: Item) -> some View {
        switch self {
        case .wardrobe:  SetWardrobeView(item: item)
        case .name:      SetNameView(item: item)
        case .category:  SetCategoryView(item: item)
        case .size:      SetSizeView(item: item)
        case .color:     SetColorView(item: item)
        case .season:    SetSeasonView(item: item)
        case .brand:     SetBrandView(item: item)
        case .price:     SetPriceView(item: item)
        case .weather:   SetWeatherView(item: item)
        case .weight:    SetWeightView(item: item)
        case .link:      SetLinkView(item: item)
        case .location:  SetLocationView(item: item)
        case .tag:       SetTagView(item: item)
        case .notes:     SetNotesView(item: item)
        }
    }
}
