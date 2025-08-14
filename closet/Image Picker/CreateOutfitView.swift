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
                            .frame(height: canvasSize)
                            .onTapGesture {
                                selectedItemId = nil
                            }
                            .clipped()

                        ForEach(canvasItems) { canvasItem in
                            CanvasItemView(
                                uiImage: uiImage(from: canvasItem.item),
                                item: canvasItem,
                                isSelected: selectedItemId == canvasItem.id,
                                onSelect: {
                                    selectedItemId = (selectedItemId == canvasItem.id) ? nil : canvasItem.id
                                },
                                onDeselect: {
                                    selectedItemId = nil
                                },
                                onRemove: {
                                    removeItemFromCanvas(canvasItem)
                                },
                                onPositionChange: { newPosition in
                                    updateItemPosition(canvasItem, newPosition: newPosition)
                                },
                                onScaleChange: { newScale in
                                    updateItemScale(canvasItem, newScale: newScale)
                                },
                                onRotationChange: { newRotation in
                                    updateItemRotation(canvasItem, newRotation: newRotation)
                                },
                                onBringToFront: {
                                    bringItemToFront(canvasItem)
                                },
                                canvasSize: canvasSize
                            )
                        }
                    }

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
                                            .cornerRadius(8)
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

struct CanvasItemView: View {
    let uiImage: UIImage?
    let item: CanvasItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDeselect: () -> Void
    let onRemove: () -> Void
    let onPositionChange: (CGPoint) -> Void
    let onScaleChange: (CGFloat) -> Void
    let onRotationChange: (Angle) -> Void
    let onBringToFront: () -> Void
    let canvasSize: CGFloat

    @State private var currentScale: CGFloat = 1.0 // For gesture tracking
    @State private var rotationAngle: Angle = .zero
    
    @State private var dragStartAngle: Angle? = nil
    @State private var dragStartDistance: CGFloat? = nil
    @State private var lastRotation: Angle = .zero
    @State private var lastScale: CGFloat = 1.0


    var body: some View {
        let totalScale = item.scale * currentScale

        ZStack {
            // CONTENT layer — gets scaled and rotated
            Group {
                if let uiImage = uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .background(Color.clear)
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                        .background(Color.clear)
                }
            }
            .scaleEffect(totalScale)
            .rotationEffect(item.rotation)
            .position(item.position)

            // UI layer — NOT scaled
            if isSelected {
                ZStack {
                    // Selection rectangle (positioned relative to image center)
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .frame(width: 100 * totalScale, height: 100 * totalScale)
                        .foregroundColor(.gray)
                       // .rotationEffect(item.rotation)
                        .position(item.position)

                    // Trash icon
                    Image(systemName: "trash.circle")
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                        .position(
                            x: item.position.x - (50 * totalScale),
                            y: item.position.y - (50 * totalScale)
                        )
                        .onTapGesture { onRemove() }

                    // Rotate & scale control icon
                    Image(systemName: "arrow.2.circlepath")
                        .frame(width: 24, height: 24)
                        .position(
                            x: item.position.x + (50 * totalScale),
                            y: item.position.y + (50 * totalScale)
                        )
                        .gesture(rotationAndScaleGesture)
                }
                .rotationEffect(item.rotation)
            }
        }

        // Drag to move position
        .gesture(
            DragGesture()
                .onChanged { value in
                    let imageSize = 100 * item.scale
                    let halfSize = imageSize / 2

                    let clampedX = min(max(value.location.x, halfSize), canvasSize - halfSize)
                    let clampedY = min(max(value.location.y, halfSize), canvasSize - halfSize)

                    onPositionChange(CGPoint(x: clampedX, y: clampedY))
                }
                .onEnded { _ in
                    onDeselect()
                }
        )
        .onTapGesture {
            onSelect()
        }
        .onLongPressGesture {
            onBringToFront()
        }
        
    }
    
    private var rotationAndScaleGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let dx = value.location.x
                let dy = value.location.y
                
                let currentAngle = Angle(radians: atan2(Double(dy), Double(dx)))
                let currentDistance = sqrt(dx * dx + dy * dy)

                if dragStartAngle == nil {
                    let startDx = value.startLocation.x
                    let startDy = value.startLocation.y
                    dragStartAngle = Angle(radians: atan2(Double(startDy), Double(startDx)))
                }

                if dragStartDistance == nil {
                    let startDx = value.startLocation.x
                    let startDy = value.startLocation.y
                    dragStartDistance = sqrt(startDx * startDx + startDy * startDy)
                }
                
                let deltaAngle = currentAngle - (dragStartAngle ?? .zero)
                let scaleRatio = currentDistance / (dragStartDistance ?? 1)

                let newRotation = lastRotation + deltaAngle
                let newScale = max(0.3, min(scaleRatio * lastScale, 4.0))

                onRotationChange(newRotation)
                onScaleChange(newScale)
            }
            .onEnded { _ in
                lastRotation = item.rotation
                lastScale = item.scale
                dragStartAngle = nil
                dragStartDistance = nil
            }
    }

    
}


