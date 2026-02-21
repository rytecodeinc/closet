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
        VStack(spacing: 20) {
            SelectionHeader(title: "Name")
            
            VStack(alignment: .leading, spacing: 12) {
                TextField("Enter item name", text: $nameText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.words)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal)
                
                HStack {
                    Spacer()
                    Button("Save") {
                        saveName()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    Spacer()
                }
            }
            
            Spacer()
        }
        .onAppear {
            nameText = item.name ?? ""
            // Focus the text field when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func saveName() {
        item.name = nameText.isEmpty ? nil : nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
                print("❌ Failed to save name: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
        
        dismiss()
    }
}

