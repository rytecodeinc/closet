//
//  OutfitDisplayView.swift
//  closet
//
//  Created by Dan Warner on 9/20/25.
//

import Foundation
import CoreData
import SwiftUI

struct OutfitDisplayView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var outfits: [Outfit] = []
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]
    
    private var squareSize = UIScreen.main.bounds.width / 2.0
    
    var body: some View {
        NavigationView {
            Group {
                if outfits.isEmpty {
                    // Fallback text if no outfits
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
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 0) {
                            ForEach(outfits, id: \.objectID) { outfit in
                                NavigationLink(destination: OutfitDetailView(outfit: outfit)) {
                                    if let imageData = outfit.image,
                                       let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(width: squareSize)
                                            .clipped()
                                            .border(.gray.opacity(0.3), width: 0.5)
                                    } else {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray5))
                                            .frame(height: 180)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundColor(.secondary)
                                            )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Looks")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                fetchOutfits()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: OutfitCanvasView()) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    // MARK: - Core Data fetch
        private func fetchOutfits() {
            let request = NSFetchRequest<Outfit>(entityName: "Outfit")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.timestamp, ascending: false)]

            do {
                let results = try viewContext.fetch(request)
                // Assign results to state on main thread (viewContext usually is main)
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
}
