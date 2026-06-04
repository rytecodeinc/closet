//
//  SetOutfitNotesView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetOutfitNotesView: View {
    @ObservedObject var outfit: Outfit
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var notesText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            SelectionPanelHeader(title: "Notes")
            
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $notesText)
                   // .frame(minHeight: 200)
                    .padding(3)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal)
                
                HStack {
                    Spacer()
                    Button("Save") {
                        saveNotes()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    Spacer()
                }
            }
            
            Spacer()
        }
        .onAppear {
            notesText = outfit.notes ?? ""
            // Focus the text field when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveNotes() {
        outfit.notes = notesText.isEmpty ? nil : notesText
        
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to save notes: \(error.localizedDescription)")
        }
        
        dismiss()
    }
}

