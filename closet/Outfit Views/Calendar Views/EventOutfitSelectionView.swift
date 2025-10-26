//
//  EventOutfitSelectionView.swift
//  closet
//
//  Created by Dan Warner on 9/20/25.
//

import SwiftUI
import CoreData

struct EventOutfitSelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var event: Event
    
    @State private var outfits: [Outfit] = []
    @State private var selectedOutfitIDs: Set<UUID> = []

    private let gridColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    
    private var squareSize = UIScreen.main.bounds.width / 2.0
    
    // MARK: - Explicit initializer
    init(event: Event) {
        self.event = event
    }

    public var body: some View {
        VStack {
            if outfits.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tshirt")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No saved outfits yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Create an outfit and save it to see it here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 6) {
                        ForEach(outfits, id: \.objectID) { outfit in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    toggleSelection(for: outfit)
                                } label: {
                                    if let imageData = outfit.image,
                                       let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(width: squareSize)
                                            .clipped()
                                            .border(selectedOutfitIDs.contains(outfit.id ?? UUID()) ? Color.blue : Color.gray.opacity(0), width: 2)
                                    } else {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray5))
                                            .frame(width: squareSize, height: squareSize)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundColor(.secondary)
                                            )
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if selectedOutfitIDs.contains(outfit.id ?? UUID()) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 20))
                                        .padding(6)
                                }
                            }
                        }
                    }
                }
            }
            
            Button("Done") {
                saveSelectedOutfits()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .navigationTitle("Select Outfits for Event")
        .onAppear {
            fetchOutfits()
            preselectExistingOutfits()
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Preselect outfits already linked to event
    private func preselectExistingOutfits() {
        if let existingOutfits = event.outfits as? Set<Outfit> {
            selectedOutfitIDs = Set(existingOutfits.compactMap { $0.id })
        }
    }
    
    // MARK: - Core Data fetch
    private func fetchOutfits() {
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.timestamp, ascending: false)]
        do {
            let results = try viewContext.fetch(request)
            DispatchQueue.main.async { self.outfits = results }
        } catch {
            print("Failed to fetch outfits: \(error)")
            DispatchQueue.main.async { self.outfits = [] }
        }
    }
    
    // MARK: - Selection
    private func toggleSelection(for outfit: Outfit) {
        guard let id = outfit.id else { return }
        if selectedOutfitIDs.contains(id) {
            selectedOutfitIDs.remove(id)
            // Also remove from event immediately
            event.removeFromOutfits(outfit)
        } else {
            selectedOutfitIDs.insert(id)
        }
    }
    
    // MARK: - Save selection to event
    private func saveSelectedOutfits() {
        let selectedOutfits = outfits.filter { selectedOutfitIDs.contains($0.id ?? UUID()) }
        for outfit in selectedOutfits {
            event.addToOutfits(outfit)
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to save outfits to event: \(error)")
        }
    }
}

