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
        VStack(spacing: 20) {
            SelectionHeader(title: "Name")
            
            VStack(alignment: .leading, spacing: 12) {
                TextField("Enter outfit name", text: $nameText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
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
            nameText = outfit.name ?? ""
            // Focus the text field when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.medium])
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

