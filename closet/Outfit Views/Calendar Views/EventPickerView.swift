//
//  PickerContentType.swift
//  closet
//
//  Created by Dan Warner on 10/18/25.
//


import SwiftUI

enum PickerContentType {
    case outfits
    case items
}

struct EventPickerView: View {
    @ObservedObject var event: Event
    let type: PickerContentType
    let imageSize: CGFloat
    let onAdd: () -> Void  // Reusable handler for the "Add" button
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: imageSize))], spacing: 2) {
            if type == .outfits {
                if let outfitsSet = event.outfits as? Set<Outfit>, !outfitsSet.isEmpty {
                    ForEach(Array(outfitsSet), id: \.objectID) { outfit in
                        if let data = outfit.image,
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: imageSize, height: imageSize)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                } else {
                    Text("No outfits selected yet.")
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if let itemsOrderedSet = event.items as? NSOrderedSet, itemsOrderedSet.count > 0 {
                    ForEach(itemsOrderedSet.array as? [Item] ?? [], id: \.objectID) { item in
                        if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                           let data = primaryPhoto.data,
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: imageSize, height: imageSize)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                } else {
                    Text("No individual items selected yet.")
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Add (+) button
            Button(action: onAdd) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray, lineWidth: 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
                    Image(systemName: "plus")
                        .font(.title)
                        .foregroundColor(.blue)
                }
                .frame(width: imageSize, height: imageSize)
            }
        }
        .padding(.horizontal)
    }
}
