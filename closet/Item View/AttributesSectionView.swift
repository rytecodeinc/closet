// MARK: - AttributesSectionView
// Single source of truth for Category, Size, Colors, Seasons, Brand, Price, Links, Location, Tags
// Works in both ItemDetailView (parent MOC) and ItemAddView (child MOC) by inheriting the ambient managedObjectContext.

import SwiftUI
import CoreData

struct AttributesSectionView: View {
    @ObservedObject var item: Item

    // One enum instead of many booleans
    @State private var activeSheet: Sheet?

    // Currency symbol (display only)
    private let currencySymbol = Locale.current.currencySymbol ?? "$"

    var body: some View {
        Section {
            categoryRow()
            sizeRow()
            colorRow()
            seasonRow()
            brandRow()
            priceRow()
            linkRow()
            locationRow()
            tagRow()
        } header: {
            Text("ATTRIBUTES").fontWeight(.semibold)
        }
        // Present the appropriate drawer; inherits environment(\.managedObjectContext)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .category:
                CategorySelectionView(item: item)
            case .size:
                SizeSelectionView(item: item)
            case .color:
                ColorSelectionView(item: item)
            case .season:
                SeasonSelectionView(item: item)
            case .brand:
                BrandSelectionView(item: item)
            case .price:
                PriceSelectionView(item: item)
            case .link:
                LinkSelectionView(item: item)
            case .location:
                LocationSelectionView(item: item)
            case .tag:
                TagSelectionView(item: item)
            }
        }
    }
}

// MARK: - Sheet enum
private extension AttributesSectionView {
    enum Sheet: Identifiable {
        case category, size, color, season, brand, price, link, location, tag
        var id: Int { hashValue }
    }
}

// MARK: - Rows
private extension AttributesSectionView {
    // Category
    func categoryRow() -> some View {
        Button { activeSheet = .category } label: {
            HStack {
                Text("Category").foregroundColor(.primary)
                Spacer()
                if let name = item.category?.name, !name.isEmpty {
                    Text(name).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
    }

    // Size (NEW unified row)
    var selectedSizeText: String? {
        guard let size = item.size, let value = size.value, !value.isEmpty else { return nil }
        if let cat = item.category, size.category == cat { return value }
        return nil
    }

    func sizeRow() -> some View {
        Button { activeSheet = .size } label: {
            HStack {
                Text("Size").foregroundColor(.primary)
                Spacer()
                if let label = selectedSizeText {
                    Text(label).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
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
                Image(systemName: "chevron.right").foregroundColor(.gray)
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
                    Text(names.prefix(2).joined(separator: ", ")).foregroundColor(.gray)
                    if names.count > 2 { Text("…").foregroundColor(.gray).font(.headline) }
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
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
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
    }

    // Price
    func priceRow() -> some View {
        Button { activeSheet = .price } label: {
            HStack {
                Text("Price").foregroundColor(.primary)
                Spacer()
                if let amount = item.price?.amount {
                    HStack(spacing: 0) {
                        Text(currencySymbol).foregroundColor(.gray)
                        Text(NumberFormatter.currency2.string(from: amount) ?? "0.00")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Image(systemName: "chevron.right").foregroundColor(.gray).padding(.leading, 4)
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
                Image(systemName: "chevron.right").foregroundColor(.gray)
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
                Image(systemName: "chevron.right").foregroundColor(.gray)
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
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Optional local formatter if you do not already have one elsewhere
// If you already have NumberFormatter.currency2 defined globally, remove this block.
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
