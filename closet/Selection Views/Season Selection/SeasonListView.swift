//
//  SeasonListView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI

struct SeasonListView: View {
    @Binding var selectedSeasonNames: Set<String>

    @FetchRequest(
        entity: Season.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Season.name, ascending: true)]
    ) private var seasons: FetchedResults<Season>

    var body: some View {
       // Section(header: SelectionHeader(title: "Select a Season")) {
            List {
                ForEach(seasons, id: \.self) { season in
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
            .navigationTitle("Select Seasons")
            .navigationBarTitleDisplayMode(.inline)
        //}
    }
}
