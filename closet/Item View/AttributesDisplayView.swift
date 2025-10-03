import SwiftUI

struct AttributesDisplayView: View {
    let item: Item
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // MARK: Category → Subcategory
            if let category = item.category {
                HStack {
                    Label("Category", systemImage: "square.grid.2x2")
                        .font(.headline)
                    Spacer()
                    Text(category.name)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
            
            if let subcategory = item.subcategory {
                HStack {
                    Label("Subcategory", systemImage: "list.bullet")
                        .font(.headline)
                    Spacer()
                    Text(subcategory.name)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // MARK: Size
            if let size = item.size {
                attributeRow(label: "Size", value: size, icon: "ruler")
            }
            
            // MARK: Color
            if let colorName = item.color {
                attributeRow(label: "Color", value: colorName, icon: "paintpalette")
            }
            
            // MARK: Season
            if let season = item.season {
                attributeRow(label: "Season", value: season, icon: "sun.max")
            }
            
            // MARK: Brand
            if let brand = item.brand {
                attributeRow(label: "Brand", value: brand, icon: "tag")
            }
            
            // MARK: Price
            if let price = item.price {
                attributeRow(label: "Price", value: "$\(price, specifier: "%.2f")", icon: "dollarsign.circle")
            }
            
            // MARK: Link
            if let link = item.link {
                HStack {
                    Label("Link", systemImage: "link")
                        .font(.headline)
                    Spacer()
                    Link("View", destination: URL(string: link)!)
                        .font(.body)
                        .foregroundColor(.blue)
                }
            }
            
            // MARK: Location
            if let location = item.location {
                attributeRow(label: "Location", value: location, icon: "mappin.and.ellipse")
            }
            
            // MARK: Tags
            if let tags = item.tags, !tags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Tags", systemImage: "number")
                        .font(.headline)
                    HStack {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func attributeRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}
