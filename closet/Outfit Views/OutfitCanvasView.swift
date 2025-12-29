//
//  CreateOutfitView.swift
//  closet
//
//  Created by Dan Warner on 8/5/25.
//

import SwiftUI
import CoreData
import Foundation
import UIKit

struct OutfitCanvasView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    // Optional outfit for editing
    let outfitToEdit: Outfit?
    
    // Wardrobe type to filter by (closet or wishlist)
    let wardrobeType: String
    
    // Fetch all wardrobes (we'll filter by type)
    @FetchRequest(
        entity: Wardrobe.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
    ) private var allWardrobes: FetchedResults<Wardrobe>
    
    // Filter wardrobes by type
    private var wardrobes: [Wardrobe] {
        allWardrobes.filter { $0.type == wardrobeType }
    }
    
    // Selected wardrobe for filtering items
    @State private var selectedWardrobe: Wardrobe?
    @State private var isWardrobeSelectionPresented = false
    
    // Fetch items filtered by selected wardrobe
    private var closetItems: [Item] {
        guard let wardrobe = selectedWardrobe else { return [] }
        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)]
        // Filter by wardrobe type: if wishlist, show wishlist items; if closet, show non-wishlist items
        if wardrobeType == "wishlist" {
            request.predicate = NSPredicate(format: "isWishlist == %@ AND ANY wardrobes == %@", NSNumber(value: true), wardrobe)
        } else {
            request.predicate = NSPredicate(format: "isWishlist == %@ AND ANY wardrobes == %@", NSNumber(value: false), wardrobe)
        }
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Failed to fetch items: \(error)")
            return []
        }
    }
    
    // State for outfit creation
    @State private var outfitItems: [OutfitItem] = []
    @State private var collageSize: CGFloat = 0
    @State private var draggedItem: OutfitItem?
    @State private var showingSaveAlert = false
    @State private var selectedItemID: UUID?
    
    // Initialize with optional outfit to edit, wardrobe type, and initial wardrobe
    init(outfitToEdit: Outfit? = nil, wardrobeType: String = "closet", initialWardrobe: Wardrobe? = nil) {
        self.outfitToEdit = outfitToEdit
        self.wardrobeType = wardrobeType
        _selectedWardrobe = State(initialValue: initialWardrobe)
    }
    
    // Calculate square collage dimensions
    private var squareSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 0
        return screenWidth - padding
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Outfit Collage Area
            outfitCollageArea
            
            // Divider
            Divider()
                .padding(.vertical, 10)
            
            // Wardrobe Selection Row
            wardrobeSelectionRow
            
            // Divider
            Divider()
            
            // Closet Items Grid
            closetItemsGrid
            
            Spacer()
        }
        .navigationTitle(outfitToEdit == nil ? "Create Outfit" : "Edit Outfit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveOutfit()
                }
                .disabled(outfitItems.isEmpty)
            }
        }
        .alert("Outfit Saved", isPresented: $showingSaveAlert) {
            Button("OK") {
                dismiss()
            }
        }
        .sheet(isPresented: $isWardrobeSelectionPresented) {
            NavigationView {
                SingleWardrobeSelectionView(selectedWardrobe: $selectedWardrobe, wardrobeType: wardrobeType)
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            // Set default wardrobe to first closet wardrobe if none selected
            if selectedWardrobe == nil, let firstWardrobe = wardrobes.first {
                selectedWardrobe = firstWardrobe
            }
            loadOutfitIfEditing()
        }
        .onChange(of: wardrobes) { newWardrobes in
            // If the selected wardrobe is no longer in the list (e.g., deleted), reset to first
            if let current = selectedWardrobe, !newWardrobes.contains(current) {
                selectedWardrobe = newWardrobes.first
            }
        }
    }
    
    // MARK: - Outfit Collage Area
    private var outfitCollageArea: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemGray6))
                .frame(width: squareSize, height: squareSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .onTapGesture { selectedItemID = nil }
            
            // Drop zone hint when empty
            if outfitItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Tap items below to add to your outfit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Outfit items
            ForEach(outfitItems.sorted(by: { $0.zIndex < $1.zIndex })) { outfitItem in
                DraggableOutfitItemView(
                    outfitItem: outfitItem,
                    collageSize: squareSize,
                    isSelected: selectedItemID == outfitItem.id,
                    onPositionChanged: { newPosition in
                        updateItemPosition(outfitItem, newPosition)
                    },
                    onScaleChanged: { newScale in
                        updateItemScale(outfitItem, newScale)
                    },
                    onRotationChanged: { newRotation in
                        updateItemRotation(outfitItem, newRotation)
                    },
                    onSelected: {
                        selectItem(outfitItem)
                    },
                    onLongPress: {
                        bringToFront(outfitItem)
                    },
                    onDelete: {
                        removeItem(outfitItem)
                    }
                )
            }
        }
    }
    
    // MARK: - Wardrobe Selection Row
    private var wardrobeSelectionRow: some View {
        Button {
            isWardrobeSelectionPresented = true
        } label: {
            HStack {
                Text("Wardrobe")
                    .foregroundColor(.primary)
                Spacer()
                if let wardrobe = selectedWardrobe {
                    Text(wardrobe.name ?? "Untitled")
                        .foregroundColor(.gray)
                } else {
                    Text("Select Wardrobe")
                        .foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Closet Items Grid
    private var closetItemsGrid: some View {
        ScrollView {
            if selectedWardrobe == nil {
                VStack {
                    Text("Please select a wardrobe")
                        .foregroundColor(.secondary)
                        .padding()
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                    ForEach(closetItems, id: \.objectID) { item in
                        ClosetItemView(item: item) {
                            addItemToOutfit(item)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Load Outfit for Editing
    private func loadOutfitIfEditing() {
        guard let outfit = outfitToEdit,
              let transformationData = outfit.transformationData else {
            return
        }
        
        // Decode the transformation data
        let decoder = JSONDecoder()
        guard let savedItems = try? decoder.decode([SavedOutfitItem].self, from: transformationData) else {
            return
        }
        
        // Reconstruct outfit items
        let items = outfit.items as? Set<Item> ?? []
        
        outfitItems = savedItems.compactMap { savedItem in
            // Find the matching item
            guard let item = items.first(where: { $0.objectID.uriRepresentation().absoluteString == savedItem.itemID }) else {
                return nil
            }
            
            return OutfitItem(
                item: item,
                position: CGPoint(x: savedItem.positionX, y: savedItem.positionY),
                scale: savedItem.scale,
                rotation: savedItem.rotation,
                zIndex: savedItem.zIndex
            )
        }
    }
    
    // MARK: - Helper Functions
    private func addItemToOutfit(_ item: Item) {
        // Check if item is already in outfit
        guard !outfitItems.contains(where: { $0.item.objectID == item.objectID }) else {
            return
        }
        
        let randomX = CGFloat.random(in: 50...(squareSize - 50))
        let randomY = CGFloat.random(in: 50...(squareSize - 50))
        
        let outfitItem = OutfitItem(
            item: item,
            position: CGPoint(x: randomX, y: randomY),
            scale: 1.0,
            rotation: 0.0,
            zIndex: outfitItems.count
        )
        
        withAnimation(.spring()) {
            outfitItems.append(outfitItem)
        }
    }
    
    private func updateItemPosition(_ outfitItem: OutfitItem, _ newPosition: CGPoint) {
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].position = newPosition
        }
    }
    
    private func updateItemScale(_ outfitItem: OutfitItem, _ newScale: CGFloat) {
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].scale = newScale
        }
    }
    
    private func updateItemRotation(_ outfitItem: OutfitItem, _ newRotation: Double) {
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].rotation = newRotation
        }
    }
    
    private func selectItem(_ outfitItem: OutfitItem) {
        selectedItemID = outfitItem.id
    }
    
    private func bringToFront(_ outfitItem: OutfitItem) {
        selectedItemID = nil
        let maxZIndex = outfitItems.map { $0.zIndex }.max() ?? 0
        
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].zIndex = maxZIndex + 1
        }
        
        selectedItemID = outfitItem.id
    }
    
    private func removeItem(_ outfitItem: OutfitItem) {
        outfitItems.removeAll { $0.id == outfitItem.id }
    }
    
    private func saveOutfit() {
        selectedItemID = nil
        
        guard let collageImage = captureCollageAsImage() else {
            print("Failed to capture collage image")
            return
        }
        
        // Use existing outfit if editing, or create new one
        let outfit = outfitToEdit ?? Outfit(context: viewContext)
        
        if outfitToEdit == nil {
            outfit.id = UUID()
        }
        outfit.timestamp = Date()
        
        // Save the collage image
        if let imageData = collageImage.pngData() {
            outfit.image = imageData
        }
        
        // Clear existing items if editing
        if outfitToEdit != nil {
            outfit.removeFromItems(outfit.items ?? NSSet())
        }
        
        // Add items to outfit
        for outfitItem in outfitItems {
            outfit.addToItems(outfitItem.item)
        }
        
        // Save transformation data
        let savedItems = outfitItems.map { outfitItem in
            SavedOutfitItem(
                itemID: outfitItem.item.objectID.uriRepresentation().absoluteString,
                positionX: outfitItem.position.x,
                positionY: outfitItem.position.y,
                scale: outfitItem.scale,
                rotation: outfitItem.rotation,
                zIndex: outfitItem.zIndex
            )
        }
        
        let encoder = JSONEncoder()
        if let transformationData = try? encoder.encode(savedItems) {
            outfit.transformationData = transformationData
        }
        
        do {
            try viewContext.save()
            showingSaveAlert = true
        } catch {
            print("Error saving outfit: \(error)")
        }
    }
    
    private func captureCollageAsImage() -> UIImage? {
        let collageView = ZStack {
            Color(red: 247/255, green: 247/255, blue: 247/255)
                    .ignoresSafeArea()
            // gray background color of outfits
            ForEach(outfitItems.sorted(by: { $0.zIndex < $1.zIndex })) { outfitItem in
                DraggableOutfitItemView(
                    outfitItem: outfitItem,
                    collageSize: squareSize,
                    isSelected: false,
                    onPositionChanged: { _ in },
                    onScaleChanged: { _ in },
                    onRotationChanged: { _ in },
                    onSelected: {},
                    onLongPress: {},
                    onDelete: {}
                )
            }
        }
        .frame(width: squareSize, height: squareSize)

        let hostingController = UIHostingController(rootView: collageView)
        hostingController.sizingOptions = .intrinsicContentSize
        hostingController.view.insetsLayoutMarginsFromSafeArea = false
        hostingController.view.frame = CGRect(origin: .zero, size: CGSize(width: squareSize, height: squareSize))
        hostingController.view.backgroundColor = .clear
        hostingController.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: squareSize, height: squareSize))
        return renderer.image { context in
            hostingController.view.drawHierarchy(in: hostingController.view.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - Saved Outfit Item Model (for JSON encoding)
struct SavedOutfitItem: Codable {
    let itemID: String
    let positionX: CGFloat
    let positionY: CGFloat
    let scale: CGFloat
    let rotation: Double
    let zIndex: Int
}

// MARK: - OutfitItem Model
struct OutfitItem: Identifiable {
    let id = UUID()
    let item: Item
    var position: CGPoint
    var scale: CGFloat
    var rotation: Double
    var zIndex: Int
}

// MARK: - Draggable Outfit Item View
struct DraggableOutfitItemView: View {
    let outfitItem: OutfitItem
    let collageSize: CGFloat
    let isSelected: Bool
    let onPositionChanged: (CGPoint) -> Void
    let onScaleChanged: (CGFloat) -> Void
    let onRotationChanged: (Double) -> Void
    let onSelected: () -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void
    
    @State private var dragOffset = CGSize.zero
    @State private var position: CGPoint
    @State private var scale: CGFloat
    @State private var baseScale: CGFloat
    @State private var rotation: Double
    @State private var baseRotation: Double
    
    private let itemSize: CGFloat = 120
    
    init(outfitItem: OutfitItem, collageSize: CGFloat, isSelected: Bool, onPositionChanged: @escaping (CGPoint) -> Void, onScaleChanged: @escaping (CGFloat) -> Void, onRotationChanged: @escaping (Double) -> Void, onSelected: @escaping () -> Void, onLongPress: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.outfitItem = outfitItem
        self.collageSize = collageSize
        self.isSelected = isSelected
        self.onPositionChanged = onPositionChanged
        self.onScaleChanged = onScaleChanged
        self.onRotationChanged = onRotationChanged
        self.onSelected = onSelected
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        self._position = State(initialValue: outfitItem.position)
        self._scale = State(initialValue: outfitItem.scale)
        self._baseScale = State(initialValue: outfitItem.scale)
        self._rotation = State(initialValue: outfitItem.rotation)
        self._baseRotation = State(initialValue: outfitItem.rotation)
    }
    
    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .frame(width: itemSize, height: itemSize)
            }
            
            if let primaryPhoto = (outfitItem.item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
               let photoData = primaryPhoto.data,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: itemSize, height: itemSize)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: itemSize, height: itemSize)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }
            
            if isSelected {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .scaleEffect(1.0 / scale)
                    }
                    Spacer()
                }
                .frame(width: itemSize + 10, height: itemSize + 10)
            }
        }
        .scaleEffect(scale)
        .rotationEffect(Angle.degrees(rotation))
        .position(x: position.x + dragOffset.width, y: position.y + dragOffset.height)
        .onTapGesture {
            onSelected()
        }
        .onLongPressGesture {
            onLongPress()
        }
        .gesture(
            isSelected ? DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let scaledItemSize = itemSize * scale
                    let newX = max(scaledItemSize/2, min(collageSize - scaledItemSize/2, position.x + value.translation.width))
                    let newY = max(scaledItemSize/2, min(collageSize - scaledItemSize/2, position.y + value.translation.height))
                    
                    let newPosition = CGPoint(x: newX, y: newY)
                    position = newPosition
                    dragOffset = .zero
                    
                    onPositionChanged(newPosition)
                } : nil
        )
        .gesture(
            isSelected ?
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(0.5, min(3.0, baseScale * value))
                    }
                    .onEnded { value in
                        let finalScale = max(0.5, min(3.0, baseScale * value))
                        scale = finalScale
                        baseScale = finalScale
                        onScaleChanged(finalScale)
                    },
                RotationGesture()
                    .onChanged { value in
                        rotation = baseRotation + value.degrees
                    }
                    .onEnded { value in
                        let finalRotation = baseRotation + value.degrees
                        rotation = finalRotation
                        baseRotation = finalRotation
                        onRotationChanged(finalRotation)
                    }
            ) : nil
        )
        .animation(.spring(), value: dragOffset)
    }
}

// MARK: - Closet Item View
struct ClosetItemView: View {
    let item: Item
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
               let photoData = primaryPhoto.data,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(height: 100)
                    .clipped()
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 100)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
/*
struct CanvasItem: Identifiable {
    let id: UUID
    let item: Item
    var position: CGPoint
    var scale: CGFloat = 1.0
    var rotation: Angle = .zero
}

struct CreateOutfitView: View {
    @State private var selectedItemId: UUID? = nil

    @Environment(\.managedObjectContext) private var viewContext

    @State private var canvasItems: [CanvasItem] = []

    let canvasSize = UIScreen.main.bounds.width

    // Add a FetchRequest to get all items that are not wishlist
        @FetchRequest(
            entity: Item.entity(),
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
            predicate: NSPredicate(format: "isWishlist == false")
        ) private var closetItems: FetchedResults<Item>

        var body: some View {
            NavigationView {
                VStack {
                    // Canvas area
                    ZStack {
                        Color.gray.opacity(0.1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItemId = nil
                            }

                        ForEach(canvasItems) { canvasItem in
                            CanvasItemView(
                                uiImage: uiImage(from: canvasItem.item),
                                item: canvasItem,
                                isSelected: selectedItemId == canvasItem.id,
                                onRemove: { removeItemFromCanvas(canvasItem) },
                                onPositionChange: { newPos in updateItemPosition(canvasItem, newPosition: newPos) },
                                onScaleChange: { newScale in updateItemScale(canvasItem, newScale: newScale) },
                                onRotationChange: { newRot in updateItemRotation(canvasItem, newRotation: newRot) },
                                onBringToFront: { bringItemToFront(canvasItem) },
                                canvasSize: canvasSize
                            )
                            .onTapGesture {
                                if selectedItemId == canvasItem.id {
                                    selectedItemId = nil
                                } else {
                                    selectedItemId = canvasItem.id
                                    bringItemToFront(canvasItem)
                                }
                            }
                            .zIndex(selectedItemId == canvasItem.id ? 1 : 0)
                        }
                    }
                    .frame(width: canvasSize, height: canvasSize)
                    .clipped() // <- Clips the whole ZStack


                    Divider()

                    // Use the @FetchRequest results directly here
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(closetItems, id: \.self) { item in
                                Button {
                                    _ = addItemToCanvas(item)
                                } label: {
                                    if let uiImage = uiImage(from: item) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 100)
                                           // .cornerRadius(8)
                                    } else {
                                        Image(systemName: "photo")
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(minWidth: 100, minHeight: 100)
                                            .clipped()
                                            .foregroundColor(.gray)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
                .navigationTitle("Outfit Collage")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Save") {
                        saveOutfit()
                    }
                }
            }
        }
    
    private func updateItemScale(_ item: CanvasItem, newScale: CGFloat) {
        if let index = canvasItems.firstIndex(where: { $0.id == item.id }) {
            canvasItems[index].scale = newScale
        }
    }


    // MARK: - Image Rendering
    func uiImage(from item: Item) -> UIImage? {
        if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
           let data = primaryPhoto.data {
            return UIImage(data: data)
        } else if let fallbackData = item.image {
            return UIImage(data: fallbackData)
        } else {
            return nil
        }
    }

    // MARK: - Data Fetching
    func fetchAllItems() -> [Item] {
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.predicate = NSPredicate(format: "isWishlist == false")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Fetch error: \(error)")
            return []
        }
    }

    // MARK: - Canvas Actions
    @discardableResult
    private func addItemToCanvas(_ item: Item) -> CanvasItem? {
        guard !canvasItems.contains(where: { $0.item.objectID == item.objectID }) else {
            print("Item already on canvas")
            return nil
        }

        // Center point of the canvas
        let center = CGPoint(x: canvasSize / 2, y: canvasSize / 2)

        let newCanvasItem = CanvasItem(id: UUID(), item: item, position: center)
        canvasItems.append(newCanvasItem)
        print("Added item to canvas: \(item.objectID)")
        return newCanvasItem
    }



    private func updateItemPosition(_ item: CanvasItem, newPosition: CGPoint) {
        if let index = canvasItems.firstIndex(where: { $0.id == item.id }) {
            canvasItems[index].position = newPosition
        }
    }

    private func updateItemRotation(_ item: CanvasItem, newRotation: Angle) {
        if let index = canvasItems.firstIndex(where: { $0.id == item.id }) {
            canvasItems[index].rotation = newRotation
        }
    }

    
    private func removeItemFromCanvas(_ item: CanvasItem) {
        canvasItems.removeAll { $0.id == item.id }
    }
    
    private func bringItemToFront(_ item: CanvasItem) {
        if let index = canvasItems.firstIndex(where: { $0.id == item.id }) {
            let movedItem = canvasItems.remove(at: index)
            canvasItems.append(movedItem) // Add to end to render on top
        }
    }


    private func saveOutfit() {
        let newOutfit = Outfit(context: viewContext)
        newOutfit.id = UUID()
        newOutfit.timestamp = Date()

        for canvasItem in canvasItems {
            newOutfit.addToItems(canvasItem.item)
        }

        do {
            try viewContext.save()
            print("Outfit saved with \(canvasItems.count) items.")
        } catch {
            print("Failed to save outfit: \(error)")
        }
    }
}

struct CanvasItemView2: View {
    let uiImage: UIImage?
    let item: CanvasItem
    let isSelected: Bool
    let onRemove: () -> Void
    let onPositionChange: (CGPoint) -> Void
    let onScaleChange: (CGFloat) -> Void
    let onRotationChange: (Angle) -> Void
    let onBringToFront: () -> Void
    let canvasSize: CGFloat

    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var liveScale: CGFloat = 1.0
    @GestureState private var liveRotation: Angle = .zero

    private let baseSide: CGFloat = 100

    var body: some View {
        ZStack {
            Group {
                if let uiImage = uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: baseSide, height: baseSide)
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: baseSide, height: baseSide)
                        .foregroundColor(.gray)
                }
            }

            if isSelected {
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(.gray)
                    .frame(width: baseSide, height: baseSide)

                Image(systemName: "trash.circle.fill")
                    .foregroundColor(.red)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(width: 28, height: 28)
                    .offset(x: -baseSide/2 - 5, y: -baseSide/2 - 5)
                    .onTapGesture { onRemove() }
            }
        }
        .scaleEffect(item.scale * liveScale)
        .rotationEffect(item.rotation + liveRotation)
        .position(
            x: item.position.x + dragOffset.width,
            y: item.position.y + dragOffset.height
        )
        .contentShape(Rectangle())
        // Only allow gestures if this item is selected
        .gesture(
            isSelected ? dragGesture.simultaneously(with: pinchGesture).simultaneously(with: rotateGesture) : nil
        )
        .onLongPressGesture { if isSelected { onBringToFront() } }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                if isSelected {
                    let newPos = CGPoint(
                        x: item.position.x + value.translation.width,
                        y: item.position.y + value.translation.height
                    )
                    onPositionChange(newPos)
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($liveScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                if isSelected {
                    onScaleChange(item.scale * value)
                }
            }
    }

    private var rotateGesture: some Gesture {
        RotationGesture()
            .updating($liveRotation) { value, state, _ in
                state = value
            }
            .onEnded { value in
                if isSelected {
                    onRotationChange(item.rotation + value)
                }
            }
    }
}



*/

