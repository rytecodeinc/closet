//
//  SeasonSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetSeasonView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @State private var selectedSeasonNames: Set<String> = []

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: item.userId)
    }

    var body: some View {
        Section(header: SelectionHeader(title: "Select Season")) {
            SeasonListView(selectedSeasonNames: $selectedSeasonNames, userId: referenceUserId)
        }
        .onAppear {
            if let seasons = item.seasons as? Set<Season> {
                selectedSeasonNames = Set(seasons.compactMap { $0.name })
            }
        }
        .onDisappear {
            // Apply season selection to item (but DON'T save context)
            applySeasonSelectionToItem()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Apply Selection
    
    private func applySeasonSelectionToItem() {
        // Remove seasons that are no longer selected
        if let existingSeasons = item.seasons as? Set<Season> {
            for season in existingSeasons {
                if !selectedSeasonNames.contains(season.name ?? "") {
                    item.removeFromSeasons(season)
                }
            }
        }

        // Add newly selected seasons
        for name in selectedSeasonNames {
            // Check if this season is already assigned
            let alreadyAssigned = (item.seasons as? Set<Season>)?.contains { $0.name == name } ?? false
            if !alreadyAssigned {
                let season = fetchOrCreateSeason(named: name)
                item.addToSeasons(season)
            }
        }
        
        // Set updatedAt since we're modifying the item
        setUpdatedAt(item)
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        // If viewContext has a parent, we're in a child context and shouldn't save
        if viewContext.parent == nil {
            // We're in a parent context (ItemDetailView), save immediately
            do {
                try viewContext.save()
                
            } catch {
                print("❌ Failed to save seasons: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
    }

    private func fetchOrCreateSeason(named name: String) -> Season {
        let request: NSFetchRequest<Season> = Season.fetchRequest()
        if let uid = referenceUserId, !uid.isEmpty {
            request.predicate = NSPredicate(format: "name ==[c] %@ AND userId == %@", name, uid)
        } else {
            request.predicate = NSPredicate(format: "name ==[c] %@", name)
        }
        do {
            if let match = try viewContext.fetch(request).first {
                return match
            }
        } catch {
            print("❌ Fetch error: \(error)")
        }

        // Create new season in the same context (child context)
        let newSeason = Season(context: viewContext)
        newSeason.name = name
        newSeason.id = UUID()
        newSeason.isVisible = true
        newSeason.userId = referenceUserId ?? item.userId
        return newSeason
    }
}
