//
//  SeasonSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//


struct SeasonSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSeasonNames: Set<String> = []

    var body: some View {
        Section(header: SelectionHeader(title: "Select a Season")) {
            SeasonListView(selectedSeasonNames: $selectedSeasonNames)
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

    // MARK: - Apply Selection (without saving)
    
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
        
        // CRITICAL: Do NOT save here
        // The changes stay in the child context
        // ItemAddView will save when user taps "Save" or rollback when user taps "Cancel"
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

        // Create new season in the same context (child context)
        let newSeason = Season(context: viewContext)
        newSeason.name = name
        newSeason.id = UUID()
        return newSeason
    }
}