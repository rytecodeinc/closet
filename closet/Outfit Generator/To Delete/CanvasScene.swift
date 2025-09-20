//
//  CanvasScene.swift
//  closet
//
//  Created by Dan Warner on 8/22/25.
//

import SwiftUI

class CanvasScene: ObservableObject {
    @Published var items: [CanvasSceneItem] = []
    @Published var selectedItemId: UUID? = nil
    
    func addItem(_ item: Item, at position: CGPoint) {
        let canvasItem = CanvasSceneItem(id: UUID(), item: item, position: position, zIndex: 0)
        items.append(canvasItem)
    }
    
    func toggleSelection(_ id: UUID) {
        if selectedItemId == id {
            // Deselect
            selectedItemId = nil
            updateZIndex(id, 0)
        } else {
            // Select
            selectedItemId = id
            updateZIndex(id, 1)
        }
    }
    
    private func updateZIndex(_ id: UUID, _ newZ: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].zIndex = newZ
    }
    
    func removeItem(_ item: CanvasSceneItem) {
        items.removeAll { $0.id == item.id }
        if selectedItemId == item.id {
            selectedItemId = nil
        }
    }

    func updateItem(_ item: CanvasSceneItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }
}

struct CanvasSceneItem: Identifiable {
    let id: UUID
    let item: Item
    var position: CGPoint
    var scale: CGFloat = 1.0
    var rotation: Angle = .zero
    var zIndex: Double = 0 // default 0
    
    var baseSize: CGFloat = 100
    
    var frame: CGRect {
        CGRect(
            x: position.x - (baseSize * scale)/2,
            y: position.y - (baseSize * scale)/2,
            width: baseSize * scale,
            height: baseSize * scale
        )
    }
}


struct CanvasSceneView: View {
    @StateObject private var scene = CanvasScene()
    
    @Environment(\.managedObjectContext) private var viewContext

    let canvasSize = UIScreen.main.bounds.width

    @FetchRequest(
        entity: Item.entity(),
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        predicate: NSPredicate(format: "isWishlist == false")
    ) private var closetItems: FetchedResults<Item>

    var body: some View {
        NavigationView {
            VStack {
                ZStack {
                    Color.gray.opacity(0.1)
                        .contentShape(Rectangle())
                        


                    ForEach(scene.items) { item in
                        CanvasItemView(
                            uiImage: uiImage(from: item.item),
                            item: item,
                            isSelected: scene.selectedItemId == item.id,
                            onRemove: { scene.removeItem(item) },
                            onPositionChange: { newPos in
                                var updated = item
                                updated.position = newPos
                                scene.updateItem(updated)
                            },
                            onScaleChange: { newScale in
                                var updated = item
                                updated.scale = newScale
                                scene.updateItem(updated)
                            },
                            onRotationChange: { newRot in
                                var updated = item
                                updated.rotation = newRot
                                scene.updateItem(updated)
                            },
                            onBringToFront: { scene.toggleSelection(item.id) },
                            canvasSize: canvasSize
                        )
                        .zIndex(item.zIndex)
                    }


                }
                .frame(width: canvasSize, height: canvasSize)
                .clipped()

                Divider()

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(closetItems, id: \.self) { item in
                            Button {
                                addItemToCanvas(item)
                            } label: {
                                if let uiImage = uiImage(from: item) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 100)
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
                Button("Save") { saveOutfit() }
            }
        }
    }

    private func addItemToCanvas(_ item: Item) {
        let center = CGPoint(x: canvasSize / 2, y: canvasSize / 2)
        scene.addItem(item, at: center)
    }

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

    private func saveOutfit() {
        let newOutfit = Outfit(context: viewContext)
        newOutfit.id = UUID()
        newOutfit.timestamp = Date()
        for canvasItem in scene.items {
            newOutfit.addToItems(canvasItem.item)
        }
        do {
            try viewContext.save()
        } catch {
            print("Failed to save outfit: \(error)")
        }
    }
}


struct CanvasItemView: View {
    let uiImage: UIImage?
    let item: CanvasSceneItem
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
        .gesture(
            TapGesture()
                .onEnded {
                    onBringToFront() // select this item
                }
        )
        .simultaneousGesture(
            isSelected ? dragGesture.simultaneously(with: pinchGesture).simultaneously(with: rotateGesture) : nil
        )

    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let newPos = CGPoint(
                    x: item.position.x + value.translation.width,
                    y: item.position.y + value.translation.height
                )
                onPositionChange(newPos)
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($liveScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                onScaleChange(item.scale * value)
            }
    }

    private var rotateGesture: some Gesture {
        RotationGesture()
            .updating($liveRotation) { value, state, _ in
                state = value
            }
            .onEnded { value in
                onRotationChange(item.rotation + value)
            }
    }
}

