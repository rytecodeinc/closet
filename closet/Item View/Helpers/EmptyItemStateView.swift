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
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showAddByTagSheet = false
    @State private var showAddByCategorySheet = false
    @State private var showMenu = false
    
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
            showMenu = true
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
