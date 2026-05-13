//
//  SizeListView.swift
//  closet
//
//  Created by Dan Warner on 1/1/25.
//

import SwiftUI
import CoreData
import Foundation

struct SizeListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedSizeValue: String?
    /// When set, only sizes owned by or used by this user's items appear.
    var userId: String? = nil
    
    @State private var sizeValues: [String] = []

    var body: some View {
        List {
            if sizeValues.isEmpty {
                Text("Sizes added to your closet will appear here.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(sizeValues, id: \.self) { sizeValue in
                    Button {
                        if selectedSizeValue == sizeValue {
                            selectedSizeValue = nil // deselect
                        } else {
                            selectedSizeValue = sizeValue // select
                        }
                    } label: {
                        HStack {
                            Text(sizeValue)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedSizeValue == sizeValue {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Size")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchSizes()
        }
    }

    private func fetchSizes() {
        let request: NSFetchRequest<Size> = Size.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Size.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Size.value, ascending: true)
        ]
        if let uid = userId {
            let owned = NSPredicate(format: "userId == %@", uid)
            let usedByUser = NSPredicate(
                format: "SUBQUERY(items, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                uid
            )
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
        }
        do {
            let allSizes = try viewContext.fetch(request)
            // Get unique size values
            var seenValues = Set<String>()
            sizeValues = allSizes.compactMap { size in
                guard let value = size.value, !value.isEmpty else { return nil }
                if seenValues.contains(value) {
                    return nil
                }
                seenValues.insert(value)
                return value
            }
        } catch {
            print("❌ Failed to fetch sizes: \(error.localizedDescription)")
            sizeValues = []
        }
    }
}

