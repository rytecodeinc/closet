//
//  EmptyStateView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//

import SwiftUI
import CoreData

struct EmptyItemStateView: View {
    @ObservedObject var wardrobe: Wardrobe
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showAddByTagSheet = false
    @State private var showAddByCategorySheet = false
    @State private var showAddFromClosetSheet = false
    @State private var hasTags = false
    @State private var hasCategories = false
    @State private var hasSourceItems = false
    
    /// Secondary closets/wishlists can bulk-add existing items by tag or category.
    private var allowsEmptyAreaBulkAddMenu: Bool {
        wardrobe.isDefault != true
    }

    private var wardrobeType: String {
        wardrobe.type ?? "closet"
    }

    private var currentUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: wardrobe.userId)
    }

    /// Bulk-add shortcuts only when the user has tagged or categorized at least one item.
    private var showQuickAddSection: Bool {
        allowsEmptyAreaBulkAddMenu && (hasTags || hasCategories)
    }

    private var addFromDefaultWardrobeLabel: String {
        (wardrobe.type ?? "closet").lowercased() == "wishlist" ? "Add from Wishlist" : "Add from Closet"
    }

    private var addFromDefaultWardrobeIcon: String {
        (wardrobe.type ?? "closet").lowercased() == "wishlist" ? "heart" : "hanger"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image("AppIconBlack")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.gray)
            Text("No saved items yet")
                .font(.headline)
                .foregroundColor(.gray)
            Text("Click the '+' button to add items")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if showQuickAddSection {
                VStack(spacing: 10) {
                    Divider()
                    Text("Quick Add")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    if hasTags {
                        Button {
                            showAddByTagSheet = true
                        } label: {
                            Label("Add by Tag", systemImage: "tag")
                                .frame(maxWidth: .infinity)
                        }
                    }

                    if hasCategories {
                        Button {
                            showAddByCategorySheet = true
                        } label: {
                            Label("Add by Category", systemImage: "square.grid.2x2")
                                .frame(maxWidth: .infinity)
                        }
                    }

                    if hasSourceItems {
                        Button {
                            showAddFromClosetSheet = true
                        } label: {
                            Label(addFromDefaultWardrobeLabel, systemImage: addFromDefaultWardrobeIcon)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshBulkAddAvailability()
        }
        .sheet(isPresented: $showAddByTagSheet) {
            AddItemsByTagView(wardrobe: wardrobe)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(authSession)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddByCategorySheet) {
            AddItemsByCategoryView(wardrobe: wardrobe)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(authSession)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddFromClosetSheet) {
            AddItemsFromDefaultWardrobeView(wardrobe: wardrobe)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(authSession)
                .presentationDetents([.medium, .large])
        }
    }

    private func refreshBulkAddAvailability() {
        guard let uid = currentUserId else {
            hasTags = false
            hasCategories = false
            hasSourceItems = false
            return
        }

        do {
            hasTags = try !viewContext.fetchTagsForItemPicker(
                userId: uid,
                wardrobeType: wardrobeType
            ).isEmpty
        } catch {
            hasTags = false
        }

        do {
            hasCategories = try !viewContext.fetchCategoriesForFilterList(userId: uid).isEmpty
        } catch {
            hasCategories = false
        }

        hasSourceItems = fetchHasAddableSourceItems(userId: uid)
    }

    private func fetchHasAddableSourceItems(userId uid: String) -> Bool {
        let type = wardrobeType.lowercased()
        guard let primary = try? WardrobeBootstrap.fetchPrimaryWardrobe(
            forType: type,
            userIdString: uid,
            in: viewContext
        ) else { return false }

        let request = NSFetchRequest<Item>(entityName: "Item")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", uid),
            NSPredicate(format: "ANY wardrobes == %@", primary),
            NSPredicate(format: "NOT (ANY wardrobes == %@)", wardrobe),
            NSPredicate(format: "isDraft != YES"),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])

        return ((try? viewContext.count(for: request)) ?? 0) > 0
    }
}
