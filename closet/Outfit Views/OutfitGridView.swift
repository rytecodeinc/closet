//
//  OutfitDisplayView.swift
//  closet
//
//  Created by Dan Warner on 9/20/25.
//

import Foundation
import CoreData
import SwiftUI

struct OutfitGridView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var outfits: [Outfit] = []
    @State private var isEditing: Bool = false // <-- tracks edit mode
    @State private var outfitToDelete: Outfit? = nil
    @State private var showingDeleteConfirmation: Bool = false
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    
    private var squareSize = UIScreen.main.bounds.width / 2.0
    
    var body: some View {
        NavigationView {
            Group {
                if outfits.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tshirt")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No saved outfits yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Outfits are collages of items from your closet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 6) {
                            ForEach(outfits, id: \.objectID) { outfit in
                                ZStack(alignment: .topTrailing) {
                                    NavigationLink(destination: OutfitDetailView(outfit: outfit)) {
                                        if let imageData = outfit.image,
                                           let uiImage = UIImage(data: imageData) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .aspectRatio(1, contentMode: .fill)
                                                .frame(width: squareSize)
                                                .clipped()
                                               // .border(.gray.opacity(0.3), width: 0.5)
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
                                    .buttonStyle(PlainButtonStyle()) // remove NavigationLink styling
                                    
                                    // Delete button overlay in edit mode
                                    if isEditing {
                                        Button {
                                            outfitToDelete = outfit
                                            showingDeleteConfirmation = true
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.system(size: 14))
                                                .padding(6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Outfits")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                fetchOutfits()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Toggle Edit Mode
                    Button(isEditing ? "Done" : "Edit") {
                        isEditing.toggle()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: OutfitCanvasView()) {
                        Image(systemName: "plus")
                    }
                }
            }
            // Confirmation alert before deleting
            .alert("Delete Outfit?", isPresented: $showingDeleteConfirmation, presenting: outfitToDelete) { outfit in
                Button("Delete", role: .destructive) {
                    deleteOutfit(outfit)
                }
                Button("Cancel", role: .cancel) {}
            } message: { outfit in
                Text("Are you sure you want to delete this outfit?")
            }
        }
    }
    
    // MARK: - Core Data fetch
     func fetchOutfits() {
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.timestamp, ascending: false)]
        
        do {
            let results = try viewContext.fetch(request)
            DispatchQueue.main.async {
                self.outfits = results
                
            }
        } catch {
            print("Failed to fetch outfits: \(error)")
            DispatchQueue.main.async {
                self.outfits = []
            }
        }
    }
    
    private func deleteOutfit(_ outfit: Outfit) {
        viewContext.delete(outfit)
        do {
            try viewContext.save()
            fetchOutfits()
        } catch {
            print("Failed to delete outfit: \(error)")
        }
    }
}

