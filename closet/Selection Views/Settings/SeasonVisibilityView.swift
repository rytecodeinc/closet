//
//  SeasonVisibilityView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import CoreData
import Foundation

struct SeasonVisibilityView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        entity: Season.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Season.name, ascending: true)]
    ) var allSeasons: FetchedResults<Season>

    var body: some View {
        List {
            ForEach(allSeasons, id: \.self) { season in
                Toggle(isOn: Binding(
                    get: { season.isVisible },
                    set: { newValue in
                        season.isVisible = newValue
                        try? viewContext.save()
                    })
                ) {
                    Text(season.name ?? "")
                        .foregroundColor(.black)
                }
            }
        }
        .navigationTitle("Seasons")
        .navigationBarTitleDisplayMode(.inline)
    }
}
