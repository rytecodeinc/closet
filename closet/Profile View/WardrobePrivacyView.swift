//
//  WardrobePrivacyView.swift
//  closet
//
//  Closet / Wishlist picker for setting per-wardrobe visibility
//  (public / friends / private). Pushed from Edit Profile via
//  `navigationDestination(item:)` — see profile-nested-navigation.mdc.
//

import SwiftUI
import CoreData

struct WardrobePrivacyView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
    ) private var allActiveWardrobes: FetchedResults<Wardrobe>

    @State private var selectedTab: String = "Closet"
    @State private var visibilityRevision = 0

    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    private var userClosets: [Wardrobe] {
        guard let uid = currentUserId else { return [] }
        return allActiveWardrobes.filter { wardrobe in
            (wardrobe.type ?? "").lowercased() == "closet" && wardrobe.userId == uid
        }
    }

    private var userWishlists: [Wardrobe] {
        guard let uid = currentUserId else { return [] }
        return allActiveWardrobes.filter { wardrobe in
            (wardrobe.type ?? "").lowercased() == "wishlist" && wardrobe.userId == uid
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if appCapabilities.showsWishlistTab {
                Picker("", selection: $selectedTab) {
                    Text("Closet (\(userClosets.count))")
                        .tag("Closet")
                    Text("Wishlist (\(userWishlists.count))")
                        .tag("Wishlist")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))

                TabView(selection: $selectedTab) {
                    wardrobePage(wardrobes: userClosets, emptyNoun: "closets")
                        .tag("Closet")
                    wardrobePage(wardrobes: userWishlists, emptyNoun: "wishlists")
                        .tag("Wishlist")
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id(visibilityRevision)
            } else {
                wardrobePage(wardrobes: userClosets, emptyNoun: "closets")
                    .id(visibilityRevision)
            }
        }
        .navigationTitle("Wardrobe Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if !appCapabilities.showsWishlistTab {
                selectedTab = "Closet"
            }
        }
    }

    @ViewBuilder
    private func wardrobePage(wardrobes: [Wardrobe], emptyNoun: String) -> some View {
        List {
            if wardrobes.isEmpty {
                Text("No \(emptyNoun) yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
            } else {
                ForEach(wardrobes, id: \.objectID) { wardrobe in
                    wardrobePrivacyRow(wardrobe)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                }
            }
        }
        .listStyle(.plain)
    }

    private func wardrobePrivacyRow(_ wardrobe: Wardrobe) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(wardrobe.name ?? "Untitled")
                    .foregroundStyle(.primary)
                Text(wardrobeSubtitle(for: wardrobe))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Menu {
                ForEach(WardrobeVisibility.allCases) { option in
                    Button {
                        updateVisibility(option, for: wardrobe)
                    } label: {
                        Label(option.menuLabel, systemImage: option.iconName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: wardrobe.wardrobeVisibility.iconName)
                    Text(wardrobe.wardrobeVisibility.menuLabel)
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Visibility, \(wardrobe.wardrobeVisibility.menuLabel)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updateVisibility(_ visibility: WardrobeVisibility, for wardrobe: Wardrobe) {
        WardrobeVisibilityPersistence.apply(
            visibility,
            to: wardrobe,
            userId: currentUserId
        )
        WardrobeVisibilityPersistence.saveAndSync(wardrobe, in: viewContext)
        visibilityRevision += 1
    }

    private func wardrobeSubtitle(for wardrobe: Wardrobe) -> String {
        let type = wardrobeTypeLabel(for: wardrobe)
        let n = nonDraftItemCount(for: wardrobe)
        let countPart = n == 1 ? "1 item" : "\(n) items"
        return "\(type) · \(countPart)"
    }

    private func wardrobeTypeLabel(for wardrobe: Wardrobe) -> String {
        switch wardrobe.type?.lowercased() {
        case "wishlist": return "Wishlist"
        default: return "Closet"
        }
    }

    private func nonDraftItemCount(for wardrobe: Wardrobe) -> Int {
        guard let uid = currentUserId else { return 0 }
        guard let set = wardrobe.items as? Set<Item> else { return 0 }
        return set.filter { item in
            item.userId == uid && itemIncludedLikeItemGrid(item)
        }.count
    }

    private func itemIncludedLikeItemGrid(_ item: Item) -> Bool {
        if item.value(forKey: "isDraft") as? Bool == true { return false }
        if item.value(forKey: "isSoftDeleted") as? Bool == true { return false }
        return true
    }
}
