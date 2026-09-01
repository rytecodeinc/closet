//
//  OotdDetailView.swift
//  closet
//
//  Read-only Outfit of the Day detail. Layout matches OotdAddView.
//

import SwiftUI
import UIKit
import CoreData

struct OotdDetailView: View {
    @ObservedObject var event: Event
    @Binding var navigationPath: NavigationPath
    @ObservedObject var tabBarHideState: TabBarHideState

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities

    @State private var isWhenExpanded = true
    @State private var isWhoExpanded = true
    @State private var refreshToken = UUID()
    @State private var heroSegment: SocialEngagementToolbarSegment = .tshirt

    private var selectedItems: [Item] {
        if let ordered = event.items as? NSOrderedSet {
            return ordered.array as? [Item] ?? []
        }
        return []
    }

    private var selectedOutfits: [Outfit] {
        guard let set = event.outfits as? Set<Outfit> else { return [] }
        return set.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var hasSelection: Bool {
        !selectedItems.isEmpty || !selectedOutfits.isEmpty
    }

    private var attributeRowInsets: EdgeInsets {
        EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)
    }

    private var dateDisplayText: String {
        let date = event.startDate ?? event.date ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        List {
            Section {
                outfitHeroRow
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                heroEngagementRow
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listSectionSpacing(4)

            if appCapabilities.enablesCloudSync {
                Section {
                    if isWhoExpanded {
                        privacyRow
                    }
                } header: {
                    sectionHeader("WHO", isExpanded: $isWhoExpanded)
                }
                .listSectionSpacing(4)
            }

            Section {
                if isWhenExpanded {
                    detailFieldRow(label: "Date", value: dateDisplayText)
                }
            } header: {
                sectionHeader("WHEN", isExpanded: $isWhenExpanded)
            }
            .listSectionSpacing(4)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .id(refreshToken)
        .background(Color(.systemBackground))
        .navigationTitle("Outfit of the Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(tabBarHideState.shouldHideTabBar ? .hidden : .automatic, for: .tabBar)
        .onAppear { tabBarHideState.shouldHideTabBar = true }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    navigationPath.append(
                        CalendarRoute.editEvent(event.objectID.uriRepresentation().absoluteString)
                    )
                }
            }
        }
        .onChange(of: navigationPath.count) { _, _ in
            viewContext.refresh(event, mergeChanges: true)
            refreshToken = UUID()
        }
    }

    // MARK: - Rows

    private var outfitHeroRow: some View {
        Color(.systemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay { heroOverlayContent }
            .clipped()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(hasSelection ? "Outfit of the day" : "No outfit selected")
    }

    @ViewBuilder
    private var heroOverlayContent: some View {
        switch heroSegment {
        case .tshirt:
            if hasSelection {
                EventSelectedItemsDisplayArea(
                    thumbnails: selectedOutfits.map { .outfit($0) }
                        + selectedItems.map { .item($0) },
                    fillsEdgeToEdge: true
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Tap to add items or outfits")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            }
        case .worn:
            if let wornImage = firstWornHeroImage {
                Image(uiImage: wornImage)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.square.badge.camera")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No worn photo")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var heroEngagementRow: some View {
        SocialEngagementActionsRow(
            segmentSelection: $heroSegment,
            showsLikeButton: false,
            showsCalendarButton: false,
            showsShareButton: false,
            showsWornSegment: true
        )
    }

    private var firstWornHeroImage: UIImage? {
        for outfit in selectedOutfits {
            if let data = outfit.wornImage, let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    private var privacyRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: event.eventVisibility.iconName)
                .foregroundColor(.gray)
                .frame(width: 22)
            Text(event.eventVisibility.menuLabel)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if event.eventVisibility == .private {
                Text("Only Me")
                    .foregroundStyle(.secondary)
            }
        }
        .listRowInsets(attributeRowInsets)
        .listRowSeparator(.hidden)
    }

    private func detailFieldRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.primary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundColor(.gray)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .listRowInsets(attributeRowInsets)
        .listRowSeparator(.hidden)
    }

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
            Spacer()
            Image(systemName: isExpanded.wrappedValue ? "minus" : "plus")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.wrappedValue.toggle()
            }
        }
    }
}
