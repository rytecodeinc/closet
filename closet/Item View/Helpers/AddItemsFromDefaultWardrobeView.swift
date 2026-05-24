//
//  AddItemsFromDefaultWardrobeView.swift
//  closet
//
//  Bulk-add items from the user's primary closet or wishlist into a secondary wardrobe.
//

import SwiftUI
import CoreData

struct AddItemsFromDefaultWardrobeView: View {
    @ObservedObject var wardrobe: Wardrobe
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var sourceItems: [Item] = []
    @State private var selectedItemIDs: Set<NSManagedObjectID> = []
    @State private var showAddConfirmation = false
    @State private var isAddingItems = false

    private var wardrobeDisplayName: String {
        wardrobe.name ?? "this wardrobe"
    }

    private var sourceWardrobeLabel: String {
        wardrobeType == "wishlist" ? "wishlist" : "closet"
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var wardrobeType: String {
        (wardrobe.type ?? "closet").lowercased()
    }

    private var navigationTitle: String {
        wardrobeType == "wishlist" ? "Add from Wishlist" : "Add from Closet"
    }

    private var emptySourceMessage: String {
        wardrobeType == "wishlist"
            ? "No items in your default wishlist yet."
            : "No items in your default closet yet."
    }

    private var currentUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: wardrobe.userId)
    }

    var body: some View {
        NavigationView {
            Group {
                if sourceItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tshirt")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(emptySourceMessage)
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 2) {
                            ForEach(sourceItems, id: \.objectID) { sourceItem in
                                Button {
                                    toggleSelection(for: sourceItem)
                                } label: {
                                    ItemView(item: sourceItem)
                                        .overlay {
                                            if isSelected(sourceItem) {
                                                VStack {
                                                    Spacer()
                                                    HStack {
                                                        Spacer()
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundColor(.blue)
                                                            .font(.system(size: 22))
                                                            .shadow(radius: 1)
                                                            .padding(8)
                                                    }
                                                }
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .disabled(isAddingItems)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isAddingItems)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        if selectedItemIDs.isEmpty {
                            dismiss()
                        } else {
                            showAddConfirmation = true
                        }
                    }
                    .disabled(isAddingItems)
                }
            }
            .onAppear {
                fetchSourceItems()
            }
            .alert("Add Items", isPresented: $showAddConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    addSelectedItems()
                }
            } message: {
                Text("Add \(selectedItemIDs.count) item\(selectedItemIDs.count == 1 ? "" : "s") from your \(sourceWardrobeLabel) to \"\(wardrobeDisplayName)\"?")
            }
        }
    }

    private func fetchSourceItems() {
        guard let uid = currentUserId else {
            sourceItems = []
            return
        }

        guard let primary = try? WardrobeBootstrap.fetchPrimaryWardrobe(
            forType: wardrobeType,
            userIdString: uid,
            in: viewContext
        ) else {
            sourceItems = []
            return
        }

        let request = NSFetchRequest<Item>(entityName: "Item")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: false)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", uid),
            NSPredicate(format: "ANY wardrobes == %@", primary),
            NSPredicate(format: "isDraft != YES"),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])

        do {
            let results = try viewContext.fetch(request)
            let primaryID = primary.objectID
            let targetID = wardrobe.objectID
            sourceItems = results.filter { item in
                guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                guard wardrobes.contains(where: { $0.objectID == primaryID }) else { return false }
                return !wardrobes.contains(where: { $0.objectID == targetID })
            }
        } catch {
            print("❌ Failed to fetch items from default wardrobe: \(error.localizedDescription)")
            sourceItems = []
        }
    }

    private func isSelected(_ item: Item) -> Bool {
        selectedItemIDs.contains(item.objectID)
    }

    private func toggleSelection(for item: Item) {
        let id = item.objectID
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func addSelectedItems() {
        let itemsToAdd = sourceItems.filter { selectedItemIDs.contains($0.objectID) }
        guard !itemsToAdd.isEmpty else {
            dismiss()
            return
        }

        isAddingItems = true

        for item in itemsToAdd {
            wardrobe.addToItems(item)
            setUpdatedAt(item)
        }
        setUpdatedAt(wardrobe)

        do {
            try viewContext.save()
            for item in itemsToAdd {
                SyncService.shared.syncItemIfNeeded(item)
            }
            dismiss()
        } catch {
            print("❌ Failed to add items to wardrobe: \(error.localizedDescription)")
            isAddingItems = false
        }
    }
}
