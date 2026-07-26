import SwiftUI

struct OutfitsViewAllSheet: View {
    let outfits: [Outfit]
    var onCreateOutfit: (() -> Void)? = nil
    let onSelect: (Outfit) -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 6) / 3 }

    var body: some View {
        VStack(spacing: 0) {
            outfitsSheetHeader

            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(outfits, id: \.objectID) { outfit in
                        Button {
                            onSelect(outfit)
                        } label: {
                            OutfitView(outfit: outfit, showsFavoriteOverlay: onCreateOutfit != nil)
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

    @ViewBuilder
    private var outfitsSheetHeader: some View {
        if let onCreateOutfit {
            SelectionPanelHeader(
                title: "Outfits",
                actionPlacement: .barAboveTitle,
                leading: { EmptyView() },
                trailing: {
                    Button(action: onCreateOutfit) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Create Outfit")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create outfit")
                }
            )
        } else {
            SelectionPanelHeader(title: "Outfits")
        }
    }
}
