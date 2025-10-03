//
//  ClosetViewTest.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI
import CoreData

struct ClosetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject var filterModel = FilterModel()
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.timestamp, ascending: true)],
        predicate: NSPredicate(format: "type == %@", "closet")
    ) private var closets: FetchedResults<Wardrobe>
    
    @State private var selectedCloset: Wardrobe?
    @State private var showClosetSheet = false
    @State private var newClosetName: String = ""
    @State private var isCreatingNewCloset = false
    
    var body: some View {
        NavigationView {
            mainContent()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationBarToolbar() }
                .onAppear { setInitialCloset() }
                .alert("New Wardrobe", isPresented: $isCreatingNewCloset) {
                    createClosetAlertButtons()
                } message: {
                    Text("Enter a name for your new closet")
                }
                .sheet(isPresented: $showClosetSheet) {
                    closetSelectionSheet()
                }
        }
    }
}

// MARK: - Body Subviews
private extension ClosetView {
    
    @ViewBuilder
    func mainContent() -> some View {
        if let selected = selectedCloset {
            ItemGridView(
                filterModel: filterModel,
                wardrobeType: "closet",
                selectedWardrobe: selected
            )
            .id(selected.objectID)
        } else {
            Text("No Closet Selected")
                .foregroundColor(.secondary)
        }
    }
    
    @ToolbarContentBuilder
    func navigationBarToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            closetSelectionButton()
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            addItemButton()
        }
    }
    
    func closetSelectionButton() -> some View {
        Button {
            showClosetSheet = true
            isCreatingNewCloset = false
        } label: {
            HStack(spacing: 4) {
                Text(selectedCloset?.name ?? "Select Closet")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.footnote)
            }
        }
    }
    
    @ViewBuilder
    func addItemButton() -> some View {
        if let selectedCloset = selectedCloset {
            NavigationLink(
                destination: ItemAddView(parentContext: viewContext, selectedWardrobe: selectedCloset)
            ) {
                Image(systemName: "plus")
            }
        }
    }
    
    /// Ensure the default "Closet" (seeded) is always used first
    func setInitialCloset() {
        if selectedCloset == nil {
            if closets.isEmpty {
                isCreatingNewCloset = true   // force first-time creation
            } else {
                selectedCloset = closets.first
            }
        }
    }

    
    func createClosetAlertButtons() -> some View {
        Group {
            TextField("i.e. Vacation, Business Trip", text: $newClosetName)
            Button("Create") {
                if let newCloset = createNewCloset(named: newClosetName) {
                    selectedCloset = newCloset
                }
                showClosetSheet = false
            }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    @ViewBuilder
    func closetSelectionSheet() -> some View {
        NavigationView {
            List {
                ForEach(closets, id: \.self) { closet in
                    Button {
                        selectedCloset = closet
                        showClosetSheet = false
                    } label: {
                        HStack {
                            Text(closet.name ?? "Untitled")
                            Spacer()
                            if closet == selectedCloset {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Your Wardrobes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newClosetName = ""
                        isCreatingNewCloset = true
                    } label: {
                        HStack {
                            Text("Add")
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func createNewCloset(named name: String) -> Wardrobe? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let newCloset = Wardrobe(context: viewContext)
        newCloset.id = UUID()
        newCloset.type = "closet"
        newCloset.name = trimmed
        newCloset.timestamp = Date()
        
        do {
            try viewContext.save()
            return newCloset
        } catch {
            print("❌ Failed to save new closet: \(error.localizedDescription)")
            return nil
        }
    }
}





