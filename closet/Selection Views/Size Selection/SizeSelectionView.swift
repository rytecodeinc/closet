//
//  SizeSelectionView.swift
//  closet
//
//  Created by Dan Warner on 8/16/25.
//


import SwiftUI
import CoreData
import Foundation

struct SizeSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSizeID: UUID?
    @State private var sizes: [Size] = []

    // Optional: control the order of sections (types)
    private let preferredScaleOrder = ["One Size", "Alpha (XXS-XXL)","US Numeric", "US Shoe"]

    var body: some View {
        VStack {
            SelectionHeader(title: "Select a Size")

            if item.category == nil {
                Text("Select a category first to see available sizes.")
                    .foregroundColor(.gray)
                    .padding()
                Spacer()
            } else if sizes.isEmpty {
                Text("No sizes are defined for \(item.category?.name ?? "this category").")
                    .foregroundColor(.gray)
                    .padding()
                Spacer()
            } else {
                List {
                    // Group by scale, then make a section per type
                    ForEach(groupedSizes(), id: \.scale) { group in
                        Section(header: sectionHeader(group.scale)) {
                            ForEach(group.items, id: \.self) { size in
                                sizeRow(size)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            refreshSizes()
            if let current = item.size, let cat = item.category, current.category == cat {
                selectedSizeID = current.id
            } else {
                selectedSizeID = nil
            }
        }
        .onChange(of: item.category?.name) { _ in
            refreshSizes()
            selectedSizeID = nil
        }
        .onDisappear {
            if let sid = selectedSizeID, let chosen = fetchSize(by: sid) {
                item.size = chosen
            } else if item.size?.category != item.category {
                item.size = nil
            }
            do { try viewContext.save() }
            catch { print("❌ Failed to save selected size: \(error)") }
        }
        .presentationDetents([.medium, .large])
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

    private func sectionHeader(_ scale: String) -> some View {
        Text(scale)
            .font(.subheadline)
            .foregroundColor(.gray)
    }

    // MARK: - Grouping

    private func groupedSizes() -> [(scale: String, items: [Size])] {
        let dict = Dictionary(grouping: sizes) { (s: Size) in (s.scale ?? "Other") }
        let keys = dict.keys.sorted { a, b in rank(a) < rank(b) || (rank(a) == rank(b) && a < b) }
        return keys.map { key in
            let sorted = (dict[key] ?? []).sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return ($0.value ?? "") < ($1.value ?? "")
            }
            return (scale: key, items: sorted)
        }
    }

    private func rank(_ scale: String) -> Int {
        preferredScaleOrder.firstIndex(of: scale) ?? Int.max
    }

    // MARK: - Helpers

    private func isSelected(_ size: Size) -> Bool {
        if let sid = selectedSizeID, let id = size.id { return sid == id }
        if let current = item.size { return current == size }
        return false
    }

    private func refreshSizes() {
        sizes.removeAll()
        guard let category = item.category else { return }

        let request: NSFetchRequest<Size> = Size.fetchRequest()
        request.predicate = NSPredicate(format: "category == %@", category)
        // Base order; final order is refined inside groupedSizes()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Size.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Size.value,     ascending: true)
        ]

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

