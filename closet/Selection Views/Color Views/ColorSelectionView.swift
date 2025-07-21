//
//  ColorSelectionView.swift
//  closet
//
//  Created by Dan Warner on 7/19/25.
//

import SwiftUI
import CoreData

struct ColorSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColorNames: Set<String> = []

    var body: some View {
        VStack {
            ColorListView(selectedColorNames: $selectedColorNames)
        }
        .onAppear {
            if let colors = item.colors as? Set<AppColor> {
                selectedColorNames = Set(colors.compactMap { $0.name })
            }
        }
        .onDisappear {
            // Sync changes back to item
            if let existingColors = item.colors as? Set<AppColor> {
                for color in existingColors {
                    if !selectedColorNames.contains(color.name ?? "") {
                        item.removeFromColors(color)
                    }
                }
            }

            for name in selectedColorNames {
                let color = fetchOrCreateColor(named: name)
                item.addToColors(color)
            }

            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save color selections: \(error)")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func fetchOrCreateColor(named name: String) -> AppColor {
        let fetchRequest: NSFetchRequest<AppColor> = AppColor.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name ==[c] %@", name)
        do {
            if let match = try viewContext.fetch(fetchRequest).first {
                return match
            }
        } catch {
            print("Fetch error: \(error)")
        }

        let newColor = AppColor(context: viewContext)
        newColor.name = name
        newColor.isVisible = true
        return newColor
    }
}


