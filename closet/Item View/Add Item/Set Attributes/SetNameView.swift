//
//  SetNameView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetNameView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var nameText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            SelectionHeader(title: "Name")

            HStack {
                TextField("Enter item name", text: $nameText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.words)
                    .focused($isTextFieldFocused)

                Button("Save") {
                    saveName()
                }
            }
            .padding(.horizontal)
            Spacer()
        }
        .onAppear {
            nameText = item.name ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .onDisappear {
            persistNameIfChanged()
        }
        .presentationDetents([.height(150)])
    }

    private func pendingNameValue() -> String? {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func storedNameValue() -> String? {
        let trimmed = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var nameHasChanged: Bool {
        pendingNameValue() != storedNameValue()
    }

    /// Writes the name to the item when it changed; persists and syncs in Item Detail context.
    private func persistNameIfChanged() {
        guard nameHasChanged else { return }

        item.name = pendingNameValue()
        setUpdatedAt(item)

        if viewContext.parent == nil {
            do {
                try viewContext.save()
                SyncService.shared.syncItemIfNeeded(item)
            } catch {
                print("❌ Failed to save name: \(error.localizedDescription)")
            }
        }
    }

    private func saveName() {
        persistNameIfChanged()
        dismiss()
    }
}

