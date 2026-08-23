//
//  ItemPackView.swift
//  closet
//
//  Pack items into storage locations.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import UIKit

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

private enum PackMoveConfirmationTarget {
    case unpacked
    case storage(PackingStorageLocation)
}

/// Payload for `fullScreenCover(item:)` so the first present isn’t blank (image travels with the item).
private struct PackingFullScreenFrontImage: Identifiable {
    let id = UUID()
    let image: UIImage?
}

struct ItemPackView: View {
    var selectedWardrobe: Wardrobe
    var wardrobeType: String
    @ObservedObject var tabBarHideState: TabBarHideState
    /// Closet tab path — Checklist appends `ItemGridFilterRoute.packingChecklist` (no sheet).
    var navigationPath: Binding<NavigationPath>? = nil
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession
    @State private var items: [Item] = []
    @State private var fullScreenFrontPresentation: PackingFullScreenFrontImage?
    @State private var fullScreenPageIndex = 0
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
    @State private var isInSelectionMode = false
    @State private var selectedItems: Set<Item> = []
    @State private var showMoveToSectionSheet = false
    /// When true, the next successful "New Storage Location" create (from Pack sheet +) assigns current selection to that location.
    @State private var assignSelectedItemsToNewStorageAfterCreate = false
    @State private var showPackMoveConfirmAlert = false
    @State private var packMoveAlertIsUnpack = false
    @State private var packMoveAlertStorageObjectID: NSManagedObjectID?
    @State private var packMoveAlertItemCount = 0
    @State private var collapsedStorageSectionIDs: Set<NSManagedObjectID> = []

    let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    /// True when every selected item is already in Unpacked (no packing assignment).
    private var selectedItemsAreAllUnpacked: Bool {
        guard !selectedItems.isEmpty else { return true }
        return selectedItems.allSatisfy { item in
            guard let itemId = item.id else { return true }
            return itemToLocation[itemId] == nil
        }
    }

    /// Single storage section for this wardrobe, if exactly one exists.
    private var soleStorageLocation: PackingStorageLocation? {
        guard storageLocations.count == 1 else { return nil }
        return storageLocations.first
    }

    /// Every selected item is already assigned to the only storage location (nowhere else to pack except Unpacked; Pack is hidden per product rule).
    private var allSelectedPackedInSoleStorageLocation: Bool {
        guard let only = soleStorageLocation, let onlyId = only.id else { return false }
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy { item in
            guard let itemId = item.id else { return false }
            return itemToLocation[itemId] == onlyId
        }
    }

    private var packToolbarButtonDisabled: Bool {
        selectedItems.isEmpty || allSelectedPackedInSoleStorageLocation
    }

    /// Selected items are all already assigned to this storage location (cannot "move" to same section).
    private func allSelectedItemsAlready(in location: PackingStorageLocation) -> Bool {
        guard !selectedItems.isEmpty, let lid = location.id else { return false }
        return selectedItems.allSatisfy { item in
            guard let itemId = item.id else { return false }
            return itemToLocation[itemId] == lid
        }
    }

    private func requestPackMoveConfirmation(target: PackMoveConfirmationTarget) {
        guard !selectedItems.isEmpty else { return }
        packMoveAlertItemCount = selectedItems.count
        switch target {
        case .unpacked:
            packMoveAlertIsUnpack = true
            packMoveAlertStorageObjectID = nil
        case .storage(let location):
            packMoveAlertIsUnpack = false
            packMoveAlertStorageObjectID = location.objectID
        }
        showPackMoveConfirmAlert = true
    }

    private var packMoveAlertConfirmButtonTitle: String {
        packMoveAlertIsUnpack ? "Unpack" : "Pack"
    }

    private var packMoveAlertMessage: String {
        let n = packMoveAlertItemCount
        if packMoveAlertIsUnpack {
            return n == 1 ? "Unpack 1 item?" : "Unpack \(n) items?"
        }
        guard let oid = packMoveAlertStorageObjectID,
              let loc = try? viewContext.existingObject(with: oid) as? PackingStorageLocation else {
            return n == 1 ? "Pack 1 item?" : "Pack \(n) items?"
        }
        let name = loc.name ?? "this section"
        return n == 1
            ? "Pack 1 item into \"\(name)\"?"
            : "Pack \(n) items into \"\(name)\"?"
    }

    private func performPendingPackMove() {
        if packMoveAlertIsUnpack {
            moveSelectedItems(to: nil)
        } else if let oid = packMoveAlertStorageObjectID,
                  let loc = try? viewContext.existingObject(with: oid) as? PackingStorageLocation {
            moveSelectedItems(to: loc)
        }
        showPackMoveConfirmAlert = false
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ItemPackEmptyStateView()
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
                    Divider()
                    unpackedSectionContent(items: itemsForLocation(nil))
                        .dropDestination(for: PackingItemRef.self) { refs, _ in
                            guard let ref = refs.first else { return false }
                            unassignItem(ref.itemId)
                            return true
                        }
                }
            }
        }
        .navigationTitle(isInSelectionMode ? "" : (selectedWardrobe.name ?? "Pack"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isInSelectionMode)
        // Always hide — conditional `.automatic` re-shows the bar if Pack `onDisappear`
        // (e.g. Checklist push) briefly clears `shouldHideTabBar`.
        .toolbar(.hidden, for: .tabBar)
        .onAppear { tabBarHideState.shouldHideTabBar = true }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                if isInSelectionMode {
                    packingSelectionModeLeadingToolbar()
                } else {
                    Button {
                        openPackingChecklist()
                    } label: {
                        Image(systemName: "pencil.and.list.clipboard")
                    }
                    .accessibilityLabel("Checklist")
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isInSelectionMode {
                    let hasSelection = !selectedItems.isEmpty
                    Button(hasSelection ? "Done" : "Cancel") {
                        isInSelectionMode = false
                        selectedItems.removeAll()
                    }
                } else {
                    Button {
                        beginSelectionMode()
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .disabled(items.isEmpty)
                    .accessibilityLabel("Select")
                    Button {
                        assignSelectedItemsToNewStorageAfterCreate = false
                        newStorageLocationName = ""
                        showAddStorageLocationAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add storage location")
                }
            }
            ToolbarItem(placement: .principal) {
                if isInSelectionMode {
                    Text("\(selectedItems.count) Selected")
                        .font(.headline)
                }
            }
            if isInSelectionMode {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showMoveToSectionSheet = true
                    } label: {
                        VStack {
                            Image(systemName: "suitcase")
                            Text("Pack")
                                .font(.caption)
                        }
                    }
                    .disabled(packToolbarButtonDisabled)
                    Button {
                        requestPackMoveConfirmation(target: .unpacked)
                    } label: {
                        VStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Unpack")
                                .font(.caption)
                        }
                    }
                    .disabled(selectedItems.isEmpty || selectedItemsAreAllUnpacked)
                }
            }
        }
        .alert("Add Storage Location", isPresented: $showAddStorageLocationAlert) {
            TextField("i.e. Carry-on luggage, Handbag", text: $newStorageLocationName)
            Button("Add") {
                createStorageLocation(named: newStorageLocationName)
                newStorageLocationName = ""
            }
            Button("Cancel", role: .cancel) {
                newStorageLocationName = ""
                assignSelectedItemsToNewStorageAfterCreate = false
            }
        } message: {
            Text("Enter a label for your bag or suitcase")
        }
        .sheet(isPresented: $showRenameStorageLocationSheet) {
            renameStorageLocationSheet()
        }
        .sheet(isPresented: $showMoveToSectionSheet) {
            moveToSectionSheet()
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
        .alert("Confirm", isPresented: $showPackMoveConfirmAlert) {
            Button("Cancel", role: .cancel) {
                showPackMoveConfirmAlert = false
            }
            Button(packMoveAlertConfirmButtonTitle) {
                performPendingPackMove()
            }
        } message: {
            Text(packMoveAlertMessage)
        }
        .onAppear {
            fetchItems()
            fetchStorageLocations()
            fetchPackingAssignments()
        }
        .onChange(of: selectedWardrobe.objectID) {
            collapsedStorageSectionIDs.removeAll()
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
        .fullScreenCover(item: $fullScreenFrontPresentation) { presentation in
            ItemFullScreenView(
                frontImage: presentation.image,
                wornImage: nil,
                selectedPageIndex: $fullScreenPageIndex,
                isPresented: Binding(
                    get: { fullScreenFrontPresentation != nil },
                    set: { if !$0 { fullScreenFrontPresentation = nil } }
                )
            )
        }
    }

    private func beginSelectionMode() {
        guard !items.isEmpty else { return }
        collapsedStorageSectionIDs.removeAll()
        isInSelectionMode = true
    }

    private func openPackingChecklist() {
        if let navigationPath {
            navigationPath.wrappedValue.append(ItemGridFilterRoute.packingChecklist)
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
        let expanded = !collapsedStorageSectionIDs.contains(location.objectID)
        Section {
            Group {
                if expanded {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(sectionItems, id: \.objectID) { item in
                            packingItemView(item)
                        }
                    }
                    .frame(minHeight: sectionItems.isEmpty ? 80 : nil)
                    .contentShape(Rectangle())
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
                } else {
                    Color.clear
                        .frame(minHeight: 1)
                        .contentShape(Rectangle())
                }
            }
        } header: {
            storageSectionHeader(location: location, sectionItems: sectionItems, isExpanded: expanded)
        }
    }

    private func toggleStorageSectionExpansion(_ location: PackingStorageLocation) {
        let id = location.objectID
        withAnimation(.easeInOut(duration: 0.28)) {
            if collapsedStorageSectionIDs.contains(id) {
                collapsedStorageSectionIDs.remove(id)
            } else {
                collapsedStorageSectionIDs.insert(id)
            }
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
            .frame(minHeight: sectionItems.isEmpty ? 80 : nil)
            .contentShape(Rectangle())
        } header: {
            sectionHeader(title: "Unpacked", sectionItems: sectionItems)
        }
    }

    @ViewBuilder
    private func packingItemView(_ item: Item) -> some View {
        if !isInSelectionMode, let itemId = item.id {
            packingItemCell(item)
                .draggable(PackingItemRef(itemId: itemId))
        } else {
            packingItemCell(item)
        }
    }

    private func packingItemCell(_ item: Item) -> some View {
        ItemView(item: item)
            .overlay(
                Group {
                    if isInSelectionMode && selectedItems.contains(item) {
                        Rectangle()
                            .fill(Color.white.opacity(0.35))
                    }
                }
            )
            .overlay(
                Group {
                    if isInSelectionMode && selectedItems.contains(item) {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.white)
                                    .background(
                                        Circle()
                                            .fill(Color.blue)
                                            .padding(2)
                                    )
                                    .font(.system(size: 22))
                                    .shadow(radius: 1)
                                    .padding(8)
                            }
                        }
                    }
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                handlePackingItemTap(item)
            }
    }

    private func handlePackingItemTap(_ item: Item) {
        if isInSelectionMode {
            if selectedItems.contains(item) {
                selectedItems.remove(item)
            } else {
                selectedItems.insert(item)
            }
            if selectedItems.isEmpty {
                isInSelectionMode = false
            }
        } else {
            presentFrontImageFullScreen(for: item)
        }
    }

    private func presentFrontImageFullScreen(for item: Item) {
        fullScreenPageIndex = 0
        fullScreenFrontPresentation = PackingFullScreenFrontImage(image: frontImage(for: item))
    }

    private func frontImage(for item: Item) -> UIImage? {
        guard let photo = ItemPhotoStorage.frontPhoto(for: item) else { return nil }
        if let data = photo.data, !data.isEmpty {
            return UIImage(data: data)
        }
        if let thumb = photo.thumbnailData, !thumb.isEmpty {
            return UIImage(data: thumb)
        }
        return nil
    }

    @ViewBuilder
    private func packingSelectionModeLeadingToolbar() -> some View {
        let allSelected = !items.isEmpty && selectedItems.count == items.count
        Button {
            if allSelected {
                selectedItems.removeAll()
                isInSelectionMode = false
            } else {
                selectedItems = Set(items)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                Text("All")
            }
        }
    }

    @ViewBuilder
    private func sectionSelectionSelectAllControl(sectionItems: [Item]) -> some View {
        if isInSelectionMode {
            let sectionSet = Set(sectionItems)
            let allSelected = !sectionItems.isEmpty && sectionItems.allSatisfy { selectedItems.contains($0) }
            Button {
                if allSelected {
                    selectedItems.subtract(sectionSet)
                    if selectedItems.isEmpty {
                        isInSelectionMode = false
                    }
                } else {
                    selectedItems.formUnion(sectionSet)
                }
            } label: {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(allSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(sectionItems.isEmpty)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, sectionItems: [Item]) -> some View {
        HStack(alignment: .center, spacing: 8) {
            sectionSelectionSelectAllControl(sectionItems: sectionItems)
            Text("\(title) (\(sectionItems.count))")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func storageSectionHeader(location: PackingStorageLocation, sectionItems: [Item], isExpanded: Bool) -> some View {
        let title = location.name ?? "Untitled"
        HStack(alignment: .center, spacing: 8) {
            sectionSelectionSelectAllControl(sectionItems: sectionItems)
            Button {
                toggleStorageSectionExpansion(location)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("\(title) (\(sectionItems.count))")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isInSelectionMode)
            Menu {
                Button {
                    unpackAllItems(in: location)
                } label: {
                    Label("Unpack All Items", systemImage: "arrow.uturn.backward")
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
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isInSelectionMode)
        }
        .padding(.horizontal)
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

    @ViewBuilder
    private func packSheetHeaderBar() -> some View {
        ZStack {
            Text("Pack")
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.top)
                .padding(.bottom)
            HStack {
                Spacer()
                Button {
                    assignSelectedItemsToNewStorageAfterCreate = !selectedItems.isEmpty
                    newStorageLocationName = ""
                    showAddStorageLocationAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    @ViewBuilder
    private func moveToSectionSheet() -> some View {
        VStack(spacing: 0) {
            packSheetHeaderBar()
            List {
                ForEach(storageLocations, id: \.objectID) { location in
                    Button {
                        requestPackMoveConfirmation(target: .storage(location))
                    } label: {
                        Text(location.name ?? "Untitled")
                    }
                    .disabled(selectedItems.isEmpty || allSelectedItemsAlready(in: location))
                }
            }
            .listStyle(.plain)
        }
        .presentationDetents([.medium])
    }

    private func moveSelectedItems(to destination: PackingStorageLocation?) {
        let targets = Array(selectedItems)
        for item in targets {
            guard let itemId = item.id else { continue }
            if let location = destination {
                assignItem(itemId, to: location)
            } else {
                unassignItem(itemId)
            }
        }
        selectedItems.removeAll()
        isInSelectionMode = false
        showMoveToSectionSheet = false
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
            print("❌ ItemPackView failed to delete storage location: \(error)")
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
            print("❌ ItemPackView failed to rename storage location: \(error)")
        }
    }
    
    private func createStorageLocation(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            assignSelectedItemsToNewStorageAfterCreate = false
            return
        }

        let location = PackingStorageLocation(context: viewContext)
        location.id = UUID()
        location.name = trimmed
        location.wardrobe = selectedWardrobe
        if let userId = authSession.userId?.uuidString {
            location.userId = userId
        }
        setCreatedAndUpdatedAt(location)

        do {
            try viewContext.save()
            fetchStorageLocations()

            let shouldAssignSelection = assignSelectedItemsToNewStorageAfterCreate
            assignSelectedItemsToNewStorageAfterCreate = false

            if shouldAssignSelection {
                let targets = Array(selectedItems)
                for item in targets {
                    guard let itemId = item.id else { continue }
                    assignItem(itemId, to: location)
                }
                selectedItems.removeAll()
                isInSelectionMode = false
                showMoveToSectionSheet = false
            }
        } catch {
            assignSelectedItemsToNewStorageAfterCreate = false
            print("❌ ItemPackView failed to create storage location: \(error)")
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
                if let userId = authSession.userId?.uuidString {
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
            print("❌ ItemPackView failed to assign item: \(error)")
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
            print("❌ ItemPackView failed to unassign item: \(error)")
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
            print("❌ ItemPackView failed to fetch packing assignments: \(error)")
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
            print("❌ ItemPackView failed to fetch storage locations: \(error)")
            DispatchQueue.main.async {
                self.storageLocations = []
            }
        }
    }
    
    private func fetchItems() {
        guard let userId = authSession.userId?.uuidString else {
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
            print("❌ ItemPackView failed to fetch items: \(error)")
            DispatchQueue.main.async {
                self.items = []
            }
        }
    }
}

// MARK: - Empty state (packing-specific; not `EmptyItemStateView` — + creates storage locations, not items)

private struct ItemPackEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "suitcase")
                .font(.system(size: 52))
                .foregroundStyle(.gray)
                .accessibilityHidden(true)
            Text("No items to pack")
                .font(.headline)
                .foregroundStyle(.gray)
            Text("Items added to this wardrobe will appear here. Tap the + button to add bags or storage locations to organize packed items.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
