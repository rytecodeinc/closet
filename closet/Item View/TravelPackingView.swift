//
//  TravelPackingView.swift
//  closet
//
//  Created for travel mode packing workflow.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// Lightweight type for drag-and-drop of items between packing sections.
private struct PackingItemRef: Codable, Transferable {
    let itemId: UUID

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .plainText) { ref in
            ref.itemId.uuidString.data(using: .utf8) ?? Data()
        } importing: { data in
            let uuidString = String(decoding: data, as: UTF8.self)
            guard let id = UUID(uuidString: uuidString) else {
                throw TransferError.invalidUUID
            }
            return PackingItemRef(itemId: id)
        }
    }

    private enum TransferError: Error {
        case invalidUUID
    }
}

struct TravelPackingView: View {
    var selectedWardrobe: Wardrobe
    var wardrobeType: String
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var items: [Item] = []
    @State private var selectedItemForNavigation: Item?
    @State private var showAddStorageLocationAlert = false
    @State private var newStorageLocationName = ""
    @State private var showRenameStorageLocationSheet = false
    @State private var editingStorageLocation: PackingStorageLocation?
    @State private var editingStorageLocationName = ""
    @State private var renameStorageLocationError = ""
    @State private var storageLocations: [PackingStorageLocation] = []
    /// Maps item ID to storage location ID. Nil/absence = Unpacked.
    @State private var itemToLocation: [UUID: UUID] = [:]
    @State private var showDeleteStorageLocationConfirmation = false
    @State private var storageLocationPendingDelete: PackingStorageLocation?
    
    let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        Group {
            if items.isEmpty {
                EmptyItemStateView(wardrobe: selectedWardrobe, wardrobeType: wardrobeType)
            } else {
                ScrollView(showsIndicators: false) {
                    ForEach(storageLocations, id: \.objectID) { location in
                        sectionContent(location: location, items: itemsForLocation(location.id))
                            .dropDestination(for: PackingItemRef.self) { refs, _ in
                                guard let ref = refs.first, let locationId = location.id else { return false }
                                assignItem(ref.itemId, to: location)
                                return true
                            }
                    }
                    unpackedSectionContent(items: itemsForLocation(nil))
                        .dropDestination(for: PackingItemRef.self) { refs, _ in
                            guard let ref = refs.first else { return false }
                            unassignItem(ref.itemId)
                            return true
                        }
                }
            }
        }
        .navigationTitle(selectedWardrobe.name ?? "Pack")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newStorageLocationName = ""
                    showAddStorageLocationAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Storage Location", isPresented: $showAddStorageLocationAlert) {
            TextField("i.e. Carry-on luggage, Handbag", text: $newStorageLocationName)
            Button("Create") {
                createStorageLocation(named: newStorageLocationName)
                newStorageLocationName = ""
            }
            Button("Cancel", role: .cancel) {
                newStorageLocationName = ""
            }
        } message: {
            Text("Enter a name for the storage container")
        }
        .sheet(isPresented: $showRenameStorageLocationSheet) {
            renameStorageLocationSheet()
        }
        .alert("Delete Section?", isPresented: $showDeleteStorageLocationConfirmation) {
            Button("Cancel", role: .cancel) {
                storageLocationPendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let location = storageLocationPendingDelete {
                    deleteStorageLocation(location)
                }
                storageLocationPendingDelete = nil
            }
        } message: {
            Text("Deleting this section will move all items in it to Unpacked.")
        }
        .onAppear {
            fetchItems()
            fetchStorageLocations()
            fetchPackingAssignments()
        }
        .onChange(of: selectedWardrobe.objectID) {
            fetchItems()
            fetchStorageLocations()
            fetchPackingAssignments()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { notification in
            if let context = notification.object as? NSManagedObjectContext,
               context === viewContext || context.parent === viewContext {
                fetchItems()
                fetchStorageLocations()
                fetchPackingAssignments()
            }
        }
        .navigationDestination(item: $selectedItemForNavigation) { item in
            ItemDetailView(item: item)
        }
    }
    
    /// Returns items for the given location. Pass `nil` for Unpacked.
    private func itemsForLocation(_ locationId: UUID?) -> [Item] {
        if let id = locationId {
            return items.filter { item in
                guard let itemId = item.id else { return false }
                return itemToLocation[itemId] == id
            }
        } else {
            return items.filter { item in
                guard let itemId = item.id else { return true }
                return itemToLocation[itemId] == nil
            }
        }
    }

    @ViewBuilder
    private func sectionContent(location: PackingStorageLocation, items sectionItems: [Item]) -> some View {
        Section {
            LazyVGrid(columns: gridColumns, spacing: 2) {
                ForEach(sectionItems, id: \.objectID) { item in
                    packingItemView(item)
                }
            }
            .padding(.top, 2)
            .frame(minHeight: sectionItems.isEmpty ? 80 : nil)
            .contentShape(Rectangle())
        } header: {
            storageSectionHeader(location: location, count: sectionItems.count)
        }
    }

    @ViewBuilder
    private func unpackedSectionContent(items sectionItems: [Item]) -> some View {
        Section {
            LazyVGrid(columns: gridColumns, spacing: 2) {
                ForEach(sectionItems, id: \.objectID) { item in
                    packingItemView(item)
                }
            }
            .padding(.top, 2)
            .frame(minHeight: sectionItems.isEmpty ? 80 : nil)
            .contentShape(Rectangle())
        } header: {
            sectionHeader("Unpacked", count: sectionItems.count)
        }
    }

    @ViewBuilder
    private func packingItemView(_ item: Item) -> some View {
        let itemView = ItemView(item: item)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedItemForNavigation = item
            }
        if let itemId = item.id {
            itemView.draggable(PackingItemRef(itemId: itemId))
        } else {
            itemView
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func storageSectionHeader(location: PackingStorageLocation, count: Int) -> some View {
        let title = location.name ?? "Untitled"
        HStack(alignment: .center, spacing: 8) {
            Text("\(title) (\(count))")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button {
                    unpackAllItems(in: location)
                } label: {
                    Label("Unpack All Items", systemImage: "arrow.uturn.up")
                }
                Button {
                    editingStorageLocation = location
                    editingStorageLocationName = location.name ?? ""
                    renameStorageLocationError = ""
                    showRenameStorageLocationSheet = true
                } label: {
                    Label("Edit Name", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    storageLocationPendingDelete = location
                    showDeleteStorageLocationConfirmation = true
                } label: {
                    Label("Delete Section", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.medium))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func renameStorageLocationSheet() -> some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                ClearButtonTextField(
                    text: $editingStorageLocationName,
                    placeholder: "Storage location name",
                    onTextChange: {
                        if !renameStorageLocationError.isEmpty {
                            renameStorageLocationError = ""
                        }
                    }
                )
                .frame(height: 36)
                .padding(.horizontal)

                if !renameStorageLocationError.isEmpty {
                    Text(renameStorageLocationError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .navigationTitle("Edit Storage Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissRenameStorageLocationSheet()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = editingStorageLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            renameStorageLocationError = "Section name cannot be blank"
                            return
                        }
                        renameStorageLocation(editingStorageLocation, to: trimmed)
                        dismissRenameStorageLocationSheet()
                    }
                }
            }
        }
        .presentationDetents([.height(150)])
    }

    private func dismissRenameStorageLocationSheet() {
        showRenameStorageLocationSheet = false
        editingStorageLocation = nil
        editingStorageLocationName = ""
        renameStorageLocationError = ""
    }

    private func deleteStorageLocation(_ location: PackingStorageLocation) {
        guard location.wardrobe == selectedWardrobe else { return }
        if let id = location.id {
            itemToLocation = itemToLocation.filter { $0.value != id }
        }
        viewContext.delete(location)
        do {
            try viewContext.save()
            fetchStorageLocations()
            fetchPackingAssignments()
        } catch {
            print("❌ TravelPackingView failed to delete storage location: \(error)")
            viewContext.rollback()
        }
    }

    private func renameStorageLocation(_ location: PackingStorageLocation?, to newName: String) {
        guard let location else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        location.name = trimmed
        setUpdatedAt(location)

        do {
            try viewContext.save()
            fetchStorageLocations()
        } catch {
            print("❌ TravelPackingView failed to rename storage location: \(error)")
        }
    }
    
    private func createStorageLocation(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let location = PackingStorageLocation(context: viewContext)
        location.id = UUID()
        location.name = trimmed
        location.wardrobe = selectedWardrobe
        if let userId = SupabaseService.shared.currentUser?.id.uuidString {
            location.userId = userId
        }
        setCreatedAndUpdatedAt(location)

        do {
            try viewContext.save()
            fetchStorageLocations()
        } catch {
            print("❌ TravelPackingView failed to create storage location: \(error)")
        }
    }

    private func assignItem(_ itemId: UUID, to location: PackingStorageLocation) {
        guard let item = items.first(where: { $0.id == itemId }) else { return }
        guard location.wardrobe == selectedWardrobe else { return }

        // Find existing assignment for this item+wardrobe, or create new
        let request = NSFetchRequest<PackingAssignment>(entityName: "PackingAssignment")
        request.predicate = NSPredicate(format: "item == %@ AND wardrobe == %@", item, selectedWardrobe)
        request.fetchLimit = 1

        do {
            let existing = try viewContext.fetch(request)
            let assignment = existing.first ?? PackingAssignment(context: viewContext)
            if existing.isEmpty {
                assignment.id = UUID()
                assignment.item = item
                assignment.wardrobe = selectedWardrobe
                if let userId = SupabaseService.shared.currentUser?.id.uuidString {
                    assignment.userId = userId
                }
                setCreatedAndUpdatedAt(assignment)
            } else {
                setUpdatedAt(assignment)
            }
            assignment.storageLocation = location

            try viewContext.save()
            itemToLocation[itemId] = location.id
        } catch {
            print("❌ TravelPackingView failed to assign item: \(error)")
        }
    }

    private func unassignItem(_ itemId: UUID) {
        guard let item = items.first(where: { $0.id == itemId }) else { return }

        let request = NSFetchRequest<PackingAssignment>(entityName: "PackingAssignment")
        request.predicate = NSPredicate(format: "item == %@ AND wardrobe == %@", item, selectedWardrobe)

        do {
            let assignments = try viewContext.fetch(request)
            for assignment in assignments {
                viewContext.delete(assignment)
            }
            try viewContext.save()
            itemToLocation.removeValue(forKey: itemId)
        } catch {
            print("❌ TravelPackingView failed to unassign item: \(error)")
        }
    }

    private func unpackAllItems(in location: PackingStorageLocation) {
        guard let locationId = location.id else { return }
        let itemIdsToUnpack = itemToLocation.filter { $0.value == locationId }.map(\.key)
        for itemId in itemIdsToUnpack {
            unassignItem(itemId)
        }
    }

    private func fetchPackingAssignments() {
        let request = NSFetchRequest<PackingAssignment>(entityName: "PackingAssignment")
        request.predicate = NSPredicate(format: "wardrobe == %@", selectedWardrobe)
        request.includesPropertyValues = true

        do {
            let assignments = try viewContext.fetch(request)
            var map: [UUID: UUID] = [:]
            for assignment in assignments {
                guard let itemId = assignment.item?.id,
                      let locationId = assignment.storageLocation?.id else { continue }
                map[itemId] = locationId
            }
            DispatchQueue.main.async {
                self.itemToLocation = map
            }
        } catch {
            print("❌ TravelPackingView failed to fetch packing assignments: \(error)")
            DispatchQueue.main.async {
                self.itemToLocation = [:]
            }
        }
    }

    private func fetchStorageLocations() {
        let request = NSFetchRequest<PackingStorageLocation>(entityName: "PackingStorageLocation")
        request.predicate = NSPredicate(format: "wardrobe == %@", selectedWardrobe)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PackingStorageLocation.createdAt, ascending: false)]

        do {
            let results = try viewContext.fetch(request)
            DispatchQueue.main.async {
                self.storageLocations = results
            }
        } catch {
            print("❌ TravelPackingView failed to fetch storage locations: \(error)")
            DispatchQueue.main.async {
                self.storageLocations = []
            }
        }
    }
    
    private func fetchItems() {
        guard let userId = SupabaseService.shared.currentUser?.id.uuidString else {
            DispatchQueue.main.async { self.items = [] }
            return
        }
        
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: true)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "ANY wardrobes == %@", selectedWardrobe),
            NSPredicate(format: "isDraft != YES"),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])
        
        do {
            let results = try viewContext.fetch(request)
            DispatchQueue.main.async {
                self.items = results
            }
        } catch {
            print("❌ TravelPackingView failed to fetch items: \(error)")
            DispatchQueue.main.async {
                self.items = []
            }
        }
    }
}
