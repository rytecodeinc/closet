//
//  EventSelectionChoiceView.swift
//  closet
//
//  Created by Dan Warner on 10/8/25.
//

import SwiftUI
import CoreData

struct EventSelectionChoiceView: View {
    @Environment(\.managedObjectContext) private var viewContext
    let event: Event

    var body: some View {
        VStack(spacing: 20) {
            
            NavigationLink("Select Outfits") {
                EventOutfitSelectionView(event: event)
                    .environment(\.managedObjectContext, viewContext)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            
            NavigationLink("Select Individual Items") {
                EventIndividualItemSelection(event: event)
                    .environment(\.managedObjectContext, viewContext)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            
            Spacer()
        }
        .navigationTitle("Choose From")
    }
}
