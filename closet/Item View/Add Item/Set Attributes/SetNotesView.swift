//
//  SetNotesView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetNotesView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var notesText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            SelectionHeader(title: "Notes")
            
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $notesText)
                    .frame(minHeight: 200)
                    .padding(4)
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
            notesText = item.notes ?? ""
            // Focus the text field when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveNotes() {
        item.notes = notesText.isEmpty ? nil : notesText
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        // If viewContext has a parent, we're in a child context and shouldn't save
        if viewContext.parent == nil {
            // We're in a parent context (ItemDetailView), save immediately
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save notes: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
        
        dismiss()
    }
}

