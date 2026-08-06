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
import UIKit

struct AttributesSectionView: View {
    @ObservedObject var item: Item
    @Environment(\.appCapabilities) private var appCapabilities

    // One enum instead of many booleans
    @Binding var activeSheet: Sheet?
    var isReadOnly: Bool = false
    /// When false, the Links row is omitted (shown as its own detail section instead).
    var includeLinks: Bool = true

    // Currency symbol (display only)
    private let currencySymbol = Locale.current.currencySymbol ?? "$"

    private var hasName: Bool {
        guard let name = item.name else { return false }
        return !name.isEmpty
    }

    private var hasCategory: Bool {
        Self.categoryDisplayText(for: item) != nil
    }

    private var hasBrand: Bool {
        guard let brand = item.brand?.name else { return false }
        return !brand.isEmpty
    }

    private var hasSize: Bool {
        selectedSizeText != nil
    }

    private var hasColors: Bool {
        guard let colors = item.colors as? Set<AppColor> else { return false }
        return !colors.isEmpty
    }

    private var hasSeasons: Bool {
        guard let seasons = item.seasons as? Set<Season> else { return false }
        return !seasons.isEmpty
    }

    private var hasLinks: Bool {
        guard let links = item.links as? Set<Link> else { return false }
        return links.contains { !($0.name ?? "").isEmpty }
    }

    private var hasTags: Bool {
        guard let tags = item.tags as? Set<Tag> else { return false }
        return tags.contains { !($0.name ?? "").isEmpty }
    }

    static func hasReadOnlyVisibleContent(for item: Item) -> Bool {
        if let name = item.name, !name.isEmpty { return true }
        if categoryDisplayText(for: item) != nil { return true }
        if let brand = item.brand?.name, !brand.isEmpty { return true }
        if let size = item.itemSize?.value, !size.isEmpty { return true }
        if let colors = item.colors as? Set<AppColor>, !colors.isEmpty { return true }
        if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty { return true }
        if let tags = item.tags as? Set<Tag>, tags.contains(where: { !($0.name ?? "").isEmpty }) { return true }
        return false
    }

    var body: some View {
        Section {
            if !isReadOnly {
                wardrobeRow()
            }
            if !isReadOnly || hasName {
                nameRow()
            }
            if !isReadOnly || hasCategory {
                categoryRow()
            }
            if !isReadOnly || hasBrand {
                brandRow()
            }
            if !isReadOnly || hasSize {
                sizeRow()
            }
            if !isReadOnly || hasColors {
                colorRow()
            }
            if !isReadOnly || hasSeasons {
                seasonRow()
            }
            if !isReadOnly {
                locationRow()
            }
            if !isReadOnly {
                priceRow()
            }
            if !isReadOnly, appCapabilities.showsWeatherAttribute {
                weatherRow()
            }
            if !isReadOnly, appCapabilities.showsWeightAttribute {
                weightRow()
            }
            if includeLinks, !isReadOnly || hasLinks {
                linkRow()
            }
            if !isReadOnly || hasTags {
                tagRow()
            }
            if !isReadOnly {
                notesRow()
            }
        }
    }
}

// MARK: - Sheet enum
extension AttributesSectionView {
    enum Sheet: String, Identifiable {
        case wardrobe, name, category, size, color, season, brand, price, link, location, tag, notes, weather, weight
        var id: String { rawValue }
    }

    static func categoryDisplayText(for item: Item) -> String? {
        guard let catName = item.category?.name, !catName.isEmpty else { return nil }
        if let sub = item.subcategory,
           sub.category == item.category,
           let subName = sub.name, !subName.isEmpty {
            return "\(catName) • \(subName)"
        }
        return catName
    }
}

// MARK: - Read-only row helpers

private struct ReadOnlyTruncatingTextRow: View {
    let title: String
    let text: String
    let sheet: AttributesSectionView.Sheet
    @Binding var activeSheet: AttributesSectionView.Sheet?
    @State private var isTruncated = false

    var body: some View {
        let content = HStack {
            Text(title).foregroundColor(.primary)
            Spacer()
            Text(text)
                .foregroundColor(.gray)
                .lineLimit(1)
                .truncationMode(.tail)
            if isTruncated {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { updateTruncation(rowWidth: geometry.size.width) }
                    .onChange(of: geometry.size.width) { _, width in
                        updateTruncation(rowWidth: width)
                    }
            }
        )

        if isTruncated {
            Button { activeSheet = sheet } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func updateTruncation(rowWidth: CGFloat) {
        guard rowWidth > 0 else { return }
        let font = UIFont.preferredFont(forTextStyle: .body)
        let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let availableWithoutChevron = rowWidth - titleWidth
        if textWidth <= availableWithoutChevron {
            isTruncated = false
            return
        }
        let availableWithChevron = rowWidth - titleWidth - 20
        isTruncated = textWidth > max(availableWithChevron, 0)
    }
}

private struct ReadOnlyColorsRow: View {
    @ObservedObject var item: Item
    @Binding var activeSheet: AttributesSectionView.Sheet?

    private var sortedColors: [AppColor] {
        guard let colors = item.colors as? Set<AppColor> else { return [] }
        return colors.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var showsDetail: Bool { sortedColors.count > 4 }

    var body: some View {
        let content = HStack {
            Text("Colors").foregroundColor(.primary)
            Spacer()
            HStack(spacing: 8) {
                ForEach(sortedColors.prefix(4), id: \.self) { appColor in
                    Circle()
                        .fill(colorFromName(appColor.name ?? ""))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                }
                if showsDetail {
                    Text("…").foregroundColor(.gray).font(.headline)
                }
            }
            if showsDetail {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }

        if showsDetail {
            Button { activeSheet = .color } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

private struct ReadOnlySeasonsRow: View {
    @ObservedObject var item: Item
    @Binding var activeSheet: AttributesSectionView.Sheet?

    private var fullText: String {
        let names = (item.seasons as? Set<Season>)?.compactMap(\.name).sorted() ?? []
        return names.joined(separator: ", ")
    }

    var body: some View {
        ReadOnlyTruncatingTextRow(
            title: "Seasons",
            text: fullText,
            sheet: .season,
            activeSheet: $activeSheet
        )
    }
}

private struct ReadOnlyLinksRow: View {
    @ObservedObject var item: Item
    @Binding var activeSheet: AttributesSectionView.Sheet?

    private var names: [String] {
        (item.links as? Set<Link>)?.compactMap(\.name).sorted() ?? []
    }

    private var fullText: String {
        names.joined(separator: ", ")
    }

    var body: some View {
        if !fullText.isEmpty {
            ReadOnlyTruncatingTextRow(
                title: "Links",
                text: fullText,
                sheet: .link,
                activeSheet: $activeSheet
            )
        }
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
                    // Dedupe by name: legacy + user-scoped rows can both be "Closet" (same label, distinct objects).
                    let names = Array(Set(wardrobes.compactMap { $0.name }.filter { !$0.isEmpty })).sorted()
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
    @ViewBuilder
    func nameRow() -> some View {
        if isReadOnly, let name = item.name, !name.isEmpty {
            ReadOnlyTruncatingTextRow(title: "Name", text: name, sheet: .name, activeSheet: $activeSheet)
        } else {
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
    }
    
    // Category
    // Helper: what to show on the right side of the row
    private var categoryDisplayText: String? {
        Self.categoryDisplayText(for: item)
    }

    // MARK: - Category Row
    @ViewBuilder
    func categoryRow() -> some View {
        if isReadOnly, let label = categoryDisplayText {
            ReadOnlyTruncatingTextRow(title: "Category", text: label, sheet: .category, activeSheet: $activeSheet)
        } else {
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Category")
                .accessibilityValue(categoryDisplayText ?? "None selected")
            }
        }
    }


    // Size (NEW unified row)
    var selectedSizeText: String? {
        guard let size = item.itemSize, let value = size.value, !value.isEmpty else { return nil }
        return value
    }

    @ViewBuilder
    func sizeRow() -> some View {
        if isReadOnly, let label = selectedSizeText {
            ReadOnlyTruncatingTextRow(title: "Size", text: label, sheet: .size, activeSheet: $activeSheet)
        } else {
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
    }

    // Colors
    @ViewBuilder
    func colorRow() -> some View {
        if isReadOnly {
            ReadOnlyColorsRow(item: item, activeSheet: $activeSheet)
        } else {
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
    }

    // Seasons
    @ViewBuilder
    func seasonRow() -> some View {
        if isReadOnly {
            ReadOnlySeasonsRow(item: item, activeSheet: $activeSheet)
        } else {
            Button { activeSheet = .season } label: {
                HStack {
                    Text("Seasons").foregroundColor(.primary)
                    Spacer()
                    if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
                        let names = seasons.compactMap { $0.name }.sorted()
                        Text(names.joined(separator: ", "))
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
    }

    // Brand
    @ViewBuilder
    func brandRow() -> some View {
        if isReadOnly, let brand = item.brand?.name, !brand.isEmpty {
            ReadOnlyTruncatingTextRow(title: "Brand", text: brand, sheet: .brand, activeSheet: $activeSheet)
        } else {
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
    }

    // Price Row
    func priceRow() -> some View {
        Button { activeSheet = .price } label: {
            HStack {
                Text("Price").foregroundColor(.primary)
                Spacer()
                if let price = item.price, let amount = price.amount {
                    Text(
                        CurrencyFormatting.displayPrice(
                            amount: amount,
                            currencyCode: price.currency ?? Locale.current.currency?.identifier ?? "USD"
                        )
                    )
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.trailing)
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
    @ViewBuilder
    func linkRow() -> some View {
        if isReadOnly {
            ReadOnlyLinksRow(item: item, activeSheet: $activeSheet)
        } else {
            let names = (item.links as? Set<Link>)?.compactMap { $0.name }.sorted() ?? []
            let display = names.prefix(2).joined(separator: ", ")
            let hasMore = names.count > 2

            Button { activeSheet = .link } label: {
                HStack {
                    Text("Links").foregroundColor(.primary)
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
    @ViewBuilder
    func tagRow() -> some View {
        if isReadOnly, let tagSet = item.tags as? Set<Tag>, !tagSet.isEmpty {
            let names = tagSet.compactMap(\.name).sorted().joined(separator: ", ")
            ReadOnlyTruncatingTextRow(title: "Tags", text: names, sheet: .tag, activeSheet: $activeSheet)
        } else {
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
    func destination(for item: Item, isReadOnly: Bool = false) -> some View {
        if isReadOnly {
            ReadOnlyAttributeDetailView(sheet: self, item: item)
        } else {
            editDestination(for: item)
        }
    }

    @ViewBuilder
    private func editDestination(for item: Item) -> some View {
        switch self {
        case .wardrobe:  SetWardrobeView(item: item)
        case .name:      SetNameView(item: item)
        case .category:  SetCategoryView(item: item)
        case .size:      SetSizeView(item: item)
        case .color:     SetColorView(item: item)
        case .season:    SetSeasonView(item: item)
        case .brand:     SetBrandView(item: item)
        case .price:     SetPriceView(item: item)
        case .weather:
            if AppEnvironment.capabilities.showsWeatherAttribute {
                SetWeatherView(item: item)
            } else {
                EmptyView()
            }
        case .weight:
            if AppEnvironment.capabilities.showsWeightAttribute {
                SetWeightView(item: item)
            } else {
                EmptyView()
            }
        case .link:
            SetLinkView(item: item)
                .presentationDetents([.medium, .large])
        case .location:  SetLocationView(item: item)
        case .tag:       SetTagView(item: item)
        case .notes:     SetNotesView(item: item)
        }
    }
}
