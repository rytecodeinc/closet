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

    @State private var seasons: [Season] = []

    var body: some View {
            List {
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
            .listStyle(.plain)
            .navigationTitle("Select Season")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: fetchSeasons)
    }
    
    private func fetchSeasons() {
        let request = NSFetchRequest<Season>(entityName: "Season")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Season.name, ascending: true)]
        do {
            seasons = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch seasons: \(error.localizedDescription)")
            seasons = []
        }
    }
}
