import SwiftUI

struct PairsViewAllSheet: View {
    let pairedItems: [Item]
    let onSelect: (Item) -> Void
    
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "Pairs")
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(pairedItems, id: \.objectID) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            ItemView(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

