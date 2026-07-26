import SwiftUI
import CoreData

private enum PairsSheetDestination: Hashable {
    case pairedItems
}

struct PairsViewAllSheet: View {
    @ObservedObject var sourceItem: Item
    var showsWardrobePicker: Bool
    var initialSegment: PairItemSelectionView.PairSourceSegment
    var allowsUnpair: Bool
    let onSelect: (Item) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var segment: PairItemSelectionView.PairSourceSegment
    @State private var path = NavigationPath()

    init(
        sourceItem: Item,
        showsWardrobePicker: Bool,
        initialSegment: PairItemSelectionView.PairSourceSegment,
        allowsUnpair: Bool,
        onSelect: @escaping (Item) -> Void
    ) {
        self.sourceItem = sourceItem
        self.showsWardrobePicker = showsWardrobePicker
        self.initialSegment = initialSegment
        self.allowsUnpair = allowsUnpair
        self.onSelect = onSelect
        _segment = State(initialValue: initialSegment)
    }

    var body: some View {
        NavigationStack(path: $path) {
            PairItemSelectionView(
                item: sourceItem,
                pairSourceSegment: $segment,
                dismissesSheetOnSuccess: true,
                onUnpairComplete: { dismiss() },
                onPairSuccess: { dismiss() },
                onShowPairedItems: { path.append(PairsSheetDestination.pairedItems) }
            )
            .navigationDestination(for: PairsSheetDestination.self) { destination in
                switch destination {
                case .pairedItems:
                    PairedItemsReviewView(
                        sourceItem: sourceItem,
                        segment: $segment,
                        allowsUnpair: allowsUnpair,
                        onSelect: onSelect,
                        onUnpairComplete: { dismiss() }
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

private struct PairedItemsReviewView: View {
    @ObservedObject var sourceItem: Item
    @Binding var segment: PairItemSelectionView.PairSourceSegment
    var allowsUnpair: Bool
    let onSelect: (Item) -> Void
    let onUnpairComplete: () -> Void

    @Environment(\.managedObjectContext) private var viewContext

    @State private var itemToUnpair: Item?
    @State private var showUnpairConfirmation = false

    private let panelBackground = Color(UIColor.secondarySystemBackground)

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var sortedPairedItems: [Item] {
        guard let pairedItemsSet = sourceItem.pairedItems as? Set<Item> else { return [] }
        let visiblePairedItems = pairedItemsSet.filter { $0.isSoftDeleted == false }
        return Array(visiblePairedItems).sorted { item1, item2 in
            let date1 = item1.updatedAt ?? Date.distantPast
            let date2 = item2.updatedAt ?? Date.distantPast
            if date1 != date2 { return date1 < date2 }
            let created1 = item1.createdAt ?? Date.distantPast
            let created2 = item2.createdAt ?? Date.distantPast
            if created1 != created2 { return created1 < created2 }
            let id1 = item1.id?.uuidString ?? ""
            let id2 = item2.id?.uuidString ?? ""
            return id1 < id2
        }
    }

    private func pairedItemIsWishlistMember(_ pairedItem: Item) -> Bool {
        (pairedItem.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
    }

    private var wishlistPairedItems: [Item] {
        sortedPairedItems.filter { pairedItemIsWishlistMember($0) }
    }

    private var closetPairedItems: [Item] {
        sortedPairedItems.filter { !pairedItemIsWishlistMember($0) }
    }

    private var displayedItems: [Item] {
        segment == .wishlist ? wishlistPairedItems : closetPairedItems
    }

    private var emptyPairsTitle: String {
        segment == .wishlist ? "No wishlist pairs yet" : "No closet pairs yet"
    }

    private var emptyPairsMessage: String {
        segment == .wishlist
            ? "This item doesn't have any wishlist pairs yet."
            : "This item doesn't have any closet pairs yet."
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker

            if displayedItems.isEmpty {
                pairsEmptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(displayedItems, id: \.objectID) { pairedItem in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    onSelect(pairedItem)
                                } label: {
                                    ItemView(item: pairedItem, showsFavoriteOverlay: allowsUnpair)
                                }
                                .buttonStyle(.plain)

                                if allowsUnpair {
                                    GridItemRemoveButton(
                                        accessibilityLabel: "Unpair item"
                                    ) {
                                        itemToUnpair = pairedItem
                                        showUnpairConfirmation = true
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .navigationTitle("Paired Items")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unpair Item", isPresented: $showUnpairConfirmation) {
            Button("Cancel", role: .cancel) {
                itemToUnpair = nil
            }
            Button("Unpair", role: .destructive) {
                if let itemToUnpair {
                    unpairItem(itemToUnpair)
                }
            }
        } message: {
            if let itemToUnpair {
                Text("Remove the pairing between \"\(itemDisplayName(sourceItem))\" and \"\(itemDisplayName(itemToUnpair))\"?")
            }
        }
    }

    private var segmentPicker: some View {
        Picker("Item Type", selection: $segment) {
            Text(PairItemSelectionView.PairSourceSegment.closet.rawValue)
                .tag(PairItemSelectionView.PairSourceSegment.closet)
            Text(PairItemSelectionView.PairSourceSegment.wishlist.rawValue)
                .tag(PairItemSelectionView.PairSourceSegment.wishlist)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(panelBackground)
    }

    private var pairsEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(emptyPairsTitle)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(emptyPairsMessage)
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

    private func unpairItem(_ itemToRemove: Item) {
        var currentPairedItems = sourceItem.pairedItems as? Set<Item> ?? []
        currentPairedItems.remove(itemToRemove)
        sourceItem.pairedItems = currentPairedItems as NSSet

        var otherItemPairedItems = itemToRemove.pairedItems as? Set<Item> ?? []
        otherItemPairedItems.remove(sourceItem)
        itemToRemove.pairedItems = otherItemPairedItems as NSSet

        do {
            setUpdatedAt(sourceItem)
            setUpdatedAt(itemToRemove)

            try viewContext.save()

            SyncService.shared.syncItemIfNeeded(sourceItem)
            SyncService.shared.syncItemIfNeeded(itemToRemove)

            itemToUnpair = nil
            onUnpairComplete()
        } catch {
            print("❌ Failed to un-pair item: \(error)")
        }
    }
}
