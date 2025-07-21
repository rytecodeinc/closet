//
//  ItemView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//

import SwiftUI
import CoreData

struct ItemView: View {
    var item: Item
    @State private var isActive: Bool = false
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        ZStack {
            NavigationLink(destination: ItemDetailView(item: item), isActive: $isActive) {
                EmptyView()
            }
            .hidden()

            if let itemImageData = item.image,
               let itemImage = UIImage(data: itemImageData) {
                Image(uiImage: itemImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .clipped()
                    .foregroundColor(.gray)
            }
        }
        .onTapGesture {
            isActive = true
        }
    }

    private func deleteItem() {
        viewContext.delete(item)
        do {
            try viewContext.save()
        } catch {
            print("Failed to delete item: \(error.localizedDescription)")
        }
    }
}
