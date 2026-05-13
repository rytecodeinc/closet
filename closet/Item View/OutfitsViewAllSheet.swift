import SwiftUI

struct OutfitsViewAllSheet: View {
    let outfits: [Outfit]
    let onSelect: (Outfit) -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 6) / 3 }

    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "Outfits")

            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(outfits, id: \.objectID) { outfit in
                        Button {
                            onSelect(outfit)
                        } label: {
                            OutfitView(outfit: outfit)
                                .frame(width: cellSize, height: cellSize)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}
