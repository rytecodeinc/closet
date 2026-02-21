//
//  SeasonSelectionView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI
import CoreData

struct SeasonSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSeasonNames: Set<String> = []

    var body: some View {
        Section(header: SelectionHeader(title: "Select Season")) {
            SeasonListView(selectedSeasonNames: $selectedSeasonNames)
        }
        .onAppear {
            if let seasons = item.seasons as? Set<Season> {
                selectedSeasonNames = Set(seasons.compactMap { $0.name })
            }
        }
        .onDisappear {
            // Remove deselected seasons
            if let existingSeasons = item.seasons as? Set<Season> {
                for season in existingSeasons {
                    if !selectedSeasonNames.contains(season.name ?? "") {
                        item.removeFromSeasons(season)
                    }
                }
            }

            // Add newly selected seasons
            for name in selectedSeasonNames {
                let season = fetchOrCreateSeason(named: name)
                item.addToSeasons(season)
            }

            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save season selections: \(error)")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func fetchOrCreateSeason(named name: String) -> Season {
        let request: NSFetchRequest<Season> = Season.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        do {
            if let match = try viewContext.fetch(request).first {
                return match
            }
        } catch {
            print("❌ Fetch error: \(error)")
        }

        let newSeason = Season(context: viewContext)
        newSeason.name = name
        newSeason.id = UUID()
        return newSeason
    }
}
