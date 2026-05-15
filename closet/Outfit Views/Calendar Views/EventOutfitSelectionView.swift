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
    @EnvironmentObject private var authSession: AuthSession

    @ObservedObject var event: Event
    
    @State private var outfits: [Outfit] = []
    @State private var selectedOutfitIDs: Set<UUID> = []

    private let gridColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    
    private var squareSize = UIScreen.main.bounds.width / 2.0
    
    private var currentUserID: String? {
        authSession.userId?.uuidString
    }
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
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.createdAt, ascending: false)]
        
        // Show only user's outfits and exclude drafts from outfit selections
        if let userID = currentUserID {
            request.predicate = NSPredicate(
                format: "isDraft != YES AND (isSoftDeleted != YES OR isSoftDeleted == nil) AND userId == %@", userID
            )
        } else {
            // Not logged in — show nothing
            print("⚠️ EventOutfitSelectionView: no logged-in user, showing no outfits")
            DispatchQueue.main.async { self.outfits = [] }
            return
        }
        
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
        syncEventUserIdFromLinkedEntities(event)
        
        // Only save context if event is already persisted (not a temporary/new event)
        if !event.objectID.isTemporaryID {
            do {
                try viewContext.save()
            } catch {
                print("Failed to save outfits to event: \(error)")
            }
        }
    }
}

