//
//  SeasonListView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import CoreData

struct SeasonListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedSeasonNames: Set<String>
    /// When set, only seasons owned by or used by this user's items appear.
    var userId: String? = nil

    @State private var seasons: [Season] = []

    var body: some View {
            List {
                if seasons.isEmpty {
                    Text("Seasons for your account will appear here.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                ForEach(seasons, id: \.objectID) { season in
                    let name = season.name ?? ""
                    
                    HStack {
                        Text(name)
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        if selectedSeasonNames.contains(name) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedSeasonNames.contains(name) {
                            selectedSeasonNames.remove(name)
                        } else {
                            selectedSeasonNames.insert(name)
                        }
                    }
                }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Season")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: fetchSeasons)
    }
    
    private func fetchSeasons() {
        let request = NSFetchRequest<Season>(entityName: "Season")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Season.name, ascending: true)]
        if let uid = userId {
            let visible = NSPredicate(format: "isVisible == YES")
            let owned = NSPredicate(format: "userId == %@", uid)
            let usedByUser = NSPredicate(
                format: "SUBQUERY(item, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                uid
            )
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                visible,
                NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser]),
            ])
        }
        do {
            let fetched = try viewContext.fetch(request)
            if let uid = userId {
                seasons = dedupeNamedReferenceRows(fetched, preferredUserId: uid)
            } else {
                seasons = fetched
            }
        } catch {
            print("❌ Failed to fetch seasons: \(error.localizedDescription)")
            seasons = []
        }
    }
}
