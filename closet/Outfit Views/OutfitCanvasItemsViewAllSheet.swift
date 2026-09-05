import SwiftUI
import CoreData

private enum OutfitCanvasSheetDestination: Hashable {
    case addedItems
}

struct OutfitCanvasItemsViewAllSheet: View {
    let items: [Item]
    var showsWardrobePicker: Bool
    var initialSegment: PairItemSelectionView.PairSourceSegment
    let wardrobeType: String
    let lockWardrobeSource: Bool
    var initialWardrobe: Wardrobe?
    let isOnCanvas: (Item) -> Bool
    let onSelect: (Item) -> Void
    let onRemove: (Item) -> Void
    let onAddItem: (Item) -> Void
    let onRemoveFromCanvas: (Item) -> Void

    @State private var segment: PairItemSelectionView.PairSourceSegment
    @State private var path = NavigationPath()

    init(
        items: [Item],
        showsWardrobePicker: Bool,
        initialSegment: PairItemSelectionView.PairSourceSegment,
        wardrobeType: String,
        lockWardrobeSource: Bool,
        initialWardrobe: Wardrobe? = nil,
        isOnCanvas: @escaping (Item) -> Bool,
        onSelect: @escaping (Item) -> Void,
        onRemove: @escaping (Item) -> Void,
        onAddItem: @escaping (Item) -> Void,
        onRemoveFromCanvas: @escaping (Item) -> Void
    ) {
        self.items = items
        self.showsWardrobePicker = showsWardrobePicker
        self.initialSegment = initialSegment
        self.wardrobeType = wardrobeType
        self.lockWardrobeSource = lockWardrobeSource
        self.initialWardrobe = initialWardrobe
        self.isOnCanvas = isOnCanvas
        self.onSelect = onSelect
        self.onRemove = onRemove
        self.onAddItem = onAddItem
        self.onRemoveFromCanvas = onRemoveFromCanvas
        _segment = State(initialValue: initialSegment)
    }

    private var itemTypeSegmentBinding: Binding<OutfitItemTypeSegment> {
        Binding(
            get: { OutfitItemTypeSegment(pairSourceSegment: segment) },
            set: { segment = $0 == .wishlist ? .wishlist : .closet }
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            OutfitItemSelectionView(
                wardrobeType: wardrobeType,
                lockWardrobeSource: lockWardrobeSource,
                initialWardrobe: initialWardrobe,
                itemTypeSegment: itemTypeSegmentBinding,
                isOnCanvas: isOnCanvas,
                canvasItemCount: items.count,
                onAddItem: onAddItem,
                onRemoveFromCanvas: onRemoveFromCanvas,
                onShowAddedItems: { path.append(OutfitCanvasSheetDestination.addedItems) }
            )
            .navigationDestination(for: OutfitCanvasSheetDestination.self) { destination in
                switch destination {
                case .addedItems:
                    OutfitAddedItemsReviewView(
                        items: items,
                        segment: $segment,
                        onSelect: onSelect,
                        onRemove: onRemove
                    )
                }
            }
        }
        .onAppear {
            segment = initialSegment
            path = NavigationPath()
        }
    }
}

private struct OutfitAddedItemsReviewView: View {
    let items: [Item]
    @Binding var segment: PairItemSelectionView.PairSourceSegment
    let onSelect: (Item) -> Void
    let onRemove: (Item) -> Void

    @State private var itemToRemove: Item?
    @State private var showRemoveConfirmation = false

    private let panelBackground = Color(UIColor.secondarySystemBackground)

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private func itemIsWishlistMember(_ item: Item) -> Bool {
        (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
    }

    private var wishlistItems: [Item] {
        items.filter { itemIsWishlistMember($0) }
    }

    private var closetItems: [Item] {
        items.filter { !itemIsWishlistMember($0) }
    }

    private var displayedItems: [Item] {
        segment == .wishlist ? wishlistItems : closetItems
    }

    private var emptyItemsTitle: String {
        segment == .wishlist ? "No wishlist items yet" : "No closet items yet"
    }

    private var emptyItemsMessage: String {
        segment == .wishlist
            ? "This outfit doesn't have any wishlist items yet."
            : "This outfit doesn't have any closet items yet."
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker

            if displayedItems.isEmpty {
                itemsEmptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(displayedItems, id: \.objectID) { canvasItem in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    onSelect(canvasItem)
                                } label: {
                                    ItemView(item: canvasItem)
                                }
                                .buttonStyle(.plain)

                                GridItemRemoveButton(
                                    accessibilityLabel: "Remove item from outfit"
                                ) {
                                    itemToRemove = canvasItem
                                    showRemoveConfirmation = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .navigationTitle("Added Items")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Remove Item", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                itemToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let itemToRemove {
                    onRemove(itemToRemove)
                    self.itemToRemove = nil
                }
            }
        } message: {
            if let itemToRemove {
                Text("Remove \"\(itemDisplayName(itemToRemove))\" from this outfit?")
            }
        }
    }

    private var segmentPicker: some View {
        HStack {
            Menu {
                Picker("Item Type", selection: $segment) {
                    Text(PairItemSelectionView.PairSourceSegment.closet.rawValue)
                        .tag(PairItemSelectionView.PairSourceSegment.closet)
                    Text(PairItemSelectionView.PairSourceSegment.wishlist.rawValue)
                        .tag(PairItemSelectionView.PairSourceSegment.wishlist)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(segment.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Item type, \(segment.rawValue)")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(panelBackground)
    }

    private var itemsEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tshirt")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(emptyItemsTitle)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(emptyItemsMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func itemDisplayName(_ item: Item) -> String {
        let trimmed = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Item" : trimmed
    }
}
