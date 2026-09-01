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
    @State private var navigationPath = NavigationPath()
    @StateObject private var itemsDraft = EventItemsSelectionDraft()
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
                EventIndividualItemSelection(event: event, navigationPath: $navigationPath)
                    .environment(\.managedObjectContext, viewContext)
                    .environmentObject(itemsDraft)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            
            Spacer()
        }
        .navigationTitle("Choose From")
    }
}
