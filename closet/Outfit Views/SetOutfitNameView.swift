//
//  SetOutfitNameView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetOutfitNameView: View {
    @ObservedObject var outfit: Outfit
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var syncService: SyncService
    
    @State private var nameText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            SelectionPanelHeader(title: "Name")

            HStack {
                TextField("Enter outfit name", text: $nameText)
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
            nameText = outfit.name ?? ""
            // Focus the text field when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.height(150)])
    }

    private func saveName() {
        outfit.name = nameText.isEmpty ? nil : nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        setUpdatedAt(outfit)
        
        do {
            try viewContext.save()
            syncService.syncOutfitIfNeeded(outfit)
        } catch {
            print("❌ Failed to save name: \(error.localizedDescription)")
        }
        
        dismiss()
    }
}

