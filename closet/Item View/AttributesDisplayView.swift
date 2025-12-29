//
//  AttributesDisplayView.swift
//  closet
//
//  Created by Dan Warner on 9/27/25.
//


import SwiftUI

struct AttributesDisplayView: View {
    @ObservedObject var item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // MARK: Brand + size
            HStack {
                if let brand = item.brand?.name {
                    Text(brand)
                        .font(.body)
                       // .fontWeight(.semibold)
                } else {
                    Text("No brand set")
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let size = item.size?.value {
                    Text(size)
                        .font(.body)
                } else {
                    Text("No size set")
                        .foregroundColor(.secondary)
                }
            }
            
            // MARK: Category + Color
            HStack {
                if let categoryName = item.category?.name {
                    if let subName = item.subcategory?.name {
                        Text("\(categoryName) • \(subName)")
                            .font(.body)
                            .foregroundColor(.primary)
                    } else {
                        Text(categoryName)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }  else {
                    Text("No category set")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                if let colors = item.colors as? Set<AppColor>, !colors.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(colors.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }), id: \.self) { appColor in
                            if let name = appColor.name {
                                Circle()
                                    .fill(colorFromName(name))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                            }
                        }
                    }
                }  else {
                    Text("No color set")
                        .foregroundColor(.secondary)
                }

            }
            
            HStack{
                // MARK: Location
                 if let location = item.location?.name {
                     Text(location)
                         .font(.body)
                 } else {
                     Text("No location set")
                         .foregroundColor(.secondary)
                 }
                Spacer()
                // MARK: Season
                VStack(alignment: .leading, spacing: 4) {
                    if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
                        let names = seasons.compactMap { $0.name }.sorted().joined(separator: ", ")
                        Text(names)
                            .font(.body)
                    }  else {
                        Text("No season set")
                            .foregroundColor(.secondary)
                    }
                }
            }
            

            HStack{
                // MARK: Links
                if let links = item.links as? Set<Link>, !links.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(links).sorted { ($0.name ?? "") < ($1.name ?? "") }, id: \.self) { link in
                            Text(link.name ?? link.url?.absoluteString ?? "")
                                .font(.body)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                if let price = item.price?.amount?.stringValue {
                    Text("$\(price)")
                        .font(.body)
                }
            }
            HStack{
                // MARK: Tags
                if let tags = item.tags as? Set<Tag>, !tags.isEmpty {
                    let names = tags.compactMap { $0.name }.sorted().joined(separator: ", ")
                    Text(names)
                        .font(.body)
                }
            }
            
            // MARK: Notes
            if let notes = item.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
            
        }
    }
}
