//
//  SingleWardrobeSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SingleWardrobeSelectionView: View {
    @Binding var selectedWardrobe: Wardrobe?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let wardrobeType: String
    
    init(selectedWardrobe: Binding<Wardrobe?>, wardrobeType: String = "closet") {
        self._selectedWardrobe = selectedWardrobe
        self.wardrobeType = wardrobeType
    }

    @FetchRequest(
        entity: Wardrobe.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
    ) private var allWardrobes: FetchedResults<Wardrobe>
    
    // Filter wardrobes by type, excluding soft-deleted and unowned wardrobes
    private var wardrobes: [Wardrobe] {
        let userId = SupabaseService.shared.currentUser?.id.uuidString
        return allWardrobes.filter {
            $0.type == wardrobeType &&
            $0.isSoftDeleted != true &&
            (userId == nil || $0.userId == userId)
        }
    }

    var body: some View {
        List {
            ForEach(wardrobes, id: \.self) { wardrobe in
                let name = wardrobe.name ?? "Untitled"
                
                Button {
                    selectedWardrobe = wardrobe
                    dismiss()
                } label: {
                    HStack {
                        Text(name)
                            .foregroundColor(.primary)
                        Spacer()
                        if wardrobe == selectedWardrobe {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Wardrobe")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Run deduplication to ensure no duplicates are shown
            deduplicateWardrobes(context: viewContext, userId: SupabaseService.shared.currentUser?.id.uuidString)
            if viewContext.hasChanges {
                try? viewContext.save()
            }
            // Refresh to update the fetched results
            viewContext.refreshAllObjects()
            viewContext.processPendingChanges()
        }
    }
}

