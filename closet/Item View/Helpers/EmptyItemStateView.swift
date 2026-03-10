//
//  EmptyStateView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//

import SwiftUI
import CoreData

struct EmptyItemStateView: View {
    @ObservedObject var wardrobe: Wardrobe
    var wardrobeType: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showAddByTagSheet = false
    @State private var showAddByCategorySheet = false
    @State private var showMenu = false
    
    // Check if this is the default wardrobe (first wardrobe of this type)
    private var isDefaultWardrobe: Bool {
        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        request.predicate = NSPredicate(format: "type == %@", wardrobeType)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)]
        
        if let firstWardrobe = try? viewContext.fetch(request).first {
            return wardrobe.objectID == firstWardrobe.objectID
        }
        return false
    }
    
    var body: some View {
        VStack {
            Spacer() // Push the content to the center
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.gray)
            Text("Click the '+' button to add items")
                .font(.headline)
                .foregroundColor(.gray)
            Spacer() // Keep it centered vertically
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it takes full height
        .contentShape(Rectangle())
        .onTapGesture {
            // Only show menu if not default wardrobe
            if !isDefaultWardrobe {
                showMenu = true
            }
        }
        .confirmationDialog("Add Items", isPresented: $showMenu, titleVisibility: .visible) {
            Button("Add by Tag") {
                showAddByTagSheet = true
            }
            Button("Add by Category") {
                showAddByCategorySheet = true
            }
        }
        .sheet(isPresented: $showAddByTagSheet) {
            AddItemsByTagView(wardrobe: wardrobe)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showAddByCategorySheet) {
            AddItemsByCategoryView(wardrobe: wardrobe)
                .environment(\.managedObjectContext, viewContext)
        }
    }
}
