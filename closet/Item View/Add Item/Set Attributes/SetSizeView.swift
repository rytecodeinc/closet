//
//  SizeSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetSizeView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSizeID: UUID?
    @State private var sizes: [Size] = []
    @State private var selectedSizeType: SizeType = .alpha

    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "Select Size")
            
            // Segmented picker for size types - always show all three options
            Picker("Size Type", selection: $selectedSizeType) {
                ForEach(SizeType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))

            if sizes.isEmpty {
                Text("No sizes are available.")
                    .foregroundColor(.gray)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(filteredAndDeduplicatedSizes(), id: \.self) { size in
                        sizeRow(size)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            refreshSizes()
            setInitialSizeType()
            if let current = item.size {
                selectedSizeID = current.id
            } else {
                selectedSizeID = nil
            }
        }
        .onDisappear {
            // Apply size selection to item (but DON'T save context)
            applySizeSelectionToItem()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Apply Selection
    
    private func applySizeSelectionToItem() {
        if let sid = selectedSizeID, let chosen = fetchSize(by: sid) {
            item.size = chosen
        } else {
            item.size = nil
        }
        
        // Set updatedAt since we're modifying the item
        setUpdatedAt(item)
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        // If viewContext has a parent, we're in a child context and shouldn't save
        if viewContext.parent == nil {
            // We're in a parent context (ItemDetailView), save immediately
            do {
                try viewContext.save()
                
                // Trigger automatic sync for the modified item
                SyncService.shared.syncItemIfNeeded(item)
            } catch {
                print("❌ Failed to save size: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
    }

    // MARK: - Row

    @ViewBuilder
    private func sizeRow(_ size: Size) -> some View {
        let label = size.value ?? ""
        HStack {
            Text(label)
                .foregroundColor(.black)
            Spacer()
            if isSelected(size) {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let id = size.id else { return }
            
            if selectedSizeID == id {
                // Deselect if tapped again
                selectedSizeID = nil
                item.size = nil
            } else {
                selectedSizeID = id
                item.size = size
            }
        }
    }

    // MARK: - Filtering and Deduplication
    
    private func filteredAndDeduplicatedSizes() -> [Size] {
        // Filter sizes by selected type
        let filtered = sizes.filter { selectedSizeType.matches(scale: $0.scale) }
        
        // Sort first to maintain order
        let sorted = filtered.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return ($0.value ?? "") < ($1.value ?? "")
        }
        
        // Remove duplicates by value, keeping the first occurrence
        // But if we encounter item.size, replace the existing entry with it
        var seenValues = Set<String>()
        var uniqueSizes: [Size] = []
        
        for size in sorted {
            if let value = size.value, !value.isEmpty {
                if !seenValues.contains(value) {
                    seenValues.insert(value)
                    uniqueSizes.append(size)
                } else if size == item.size {
                    // If this is the current item's size and we've already seen this value,
                    // replace the existing entry with this one
                    if let index = uniqueSizes.firstIndex(where: { $0.value == value }) {
                        uniqueSizes[index] = size
                    }
                }
            }
        }
        
        return uniqueSizes
    }
    
    private func setInitialSizeType() {
        // If current size matches a type, select that type
        if let currentSize = item.size, let scale = currentSize.scale {
            if SizeType.alpha.matches(scale: scale) {
                selectedSizeType = .alpha
            } else if SizeType.numeric.matches(scale: scale) {
                selectedSizeType = .numeric
            } else if SizeType.shoe.matches(scale: scale) {
                selectedSizeType = .shoe
            }
        }
        // Otherwise default to alpha
    }

    // MARK: - Helpers

    private func isSelected(_ size: Size) -> Bool {
        if let sid = selectedSizeID, let id = size.id { return sid == id }
        if let current = item.size { return current == size }
        return false
    }

    private func refreshSizes() {
        sizes.removeAll()

        let request: NSFetchRequest<Size> = Size.fetchRequest()
        // Fetch all sizes regardless of category
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Size.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Size.value,     ascending: true)
        ]
        if let uid = item.userId, !uid.isEmpty {
            let owned = NSPredicate(format: "userId == %@", uid)
            let usedByUser = NSPredicate(
                format: "SUBQUERY(items, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                uid
            )
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
        }

        do { sizes = try viewContext.fetch(request) }
        catch {
            print("❌ Failed to fetch sizes: \(error)")
            sizes = []
        }
    }

    private func fetchSize(by id: UUID) -> Size? {
        let req: NSFetchRequest<Size> = Size.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? viewContext.fetch(req).first
    }
}
