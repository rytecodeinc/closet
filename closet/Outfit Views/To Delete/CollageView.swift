//
//  CollageView.swift
//  closet
//
//  Created by Dan Warner on 8/17/25.
//


import SwiftUI
import CoreData
import UniformTypeIdentifiers

import SwiftUI
import CoreData

// MARK: - Collage Element
/*
struct CollageElement: Identifiable, Equatable {
    let id: UUID
    let itemID: NSManagedObjectID
    var image: UIImage

    // Canvas state
    var position: CGPoint      // in canvas coordinates
    var scale: CGFloat
    var rotation: Angle
}

// MARK: - View Model

final class CollageViewModel: ObservableObject {
    @Published var elements: [CollageElement] = []
    @Published var selectedElementID: UUID? = nil

    // Public read-only set of featured item IDs for persistence / detail view use.
    var featuredItemIDs: Set<NSManagedObjectID> {
        Set(elements.map { $0.itemID })
    }

    func add(item: Item, in canvasSize: CGSize) {
        guard let uiImage = Self.primaryImage(for: item) else { return }

        // Place new element roughly center of canvas.
        let center = CGPoint(x: canvasSize.width / 2.0, y: canvasSize.height / 2.0)

        let element = CollageElement(
            id: UUID(),
            itemID: item.objectID,
            image: uiImage,
            position: center,
            scale: 1.0,
            rotation: .degrees(0)
        )
        elements.append(element)
        selectedElementID = element.id
    }

    func select(_ id: UUID) {
        selectedElementID = id
    }

    func update(id: UUID, position: CGPoint? = nil, scale: CGFloat? = nil, rotation: Angle? = nil) {
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return }
        if let position = position { elements[idx].position = position }
        if let scale = scale { elements[idx].scale = scale }
        if let rotation = rotation { elements[idx].rotation = rotation }
    }

    private static func primaryImage(for item: Item) -> UIImage? {
        guard
            let photos = item.photos as? Set<Photo>,
            let primary = photos.first(where: { $0.isPrimary }),
            let data = primary.data,
            let image = UIImage(data: data)
        else { return nil }
        return image
    }
}

// MARK: - Canvas Item View

private struct CanvasItemView3: View {
    @ObservedObject var vm: CollageViewModel
    var element: CollageElement
    let canvasSize: CGSize

    // Gesture local state
    @State private var startPosition: CGPoint = .zero
    @State private var startScale: CGFloat = 1.0
    @State private var startRotation: Angle = .degrees(0)

    var isSelected: Bool { vm.selectedElementID == element.id }

    var body: some View {
        let drag = DragGesture()
            .onChanged { value in
                let newPos = CGPoint(x: startPosition.x + value.translation.width,
                                     y: startPosition.y + value.translation.height)
                vm.update(id: element.id, position: clampToCanvas(newPos))
            }
            .onEnded { _ in
                // Commit already applied via .onChanged
            }

        let magnify = MagnificationGesture()
            .onChanged { factor in
                vm.update(id: element.id, scale: max(0.2, min(5.0, startScale * factor)))
            }

        let rotate = RotationGesture()
            .onChanged { angle in
                vm.update(id: element.id, rotation: startRotation + angle)
            }

        Image(uiImage: element.image)
            .resizable()
            .scaledToFit()
            .frame(width: element.image.size.width, height: element.image.size.height)
            .scaleEffect(element.scale)
            .rotationEffect(element.rotation)
            .position(element.position)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(.blue)
                        .scaleEffect(element.scale)
                        .rotationEffect(element.rotation)
                        .position(element.position)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle()) // precise hit testing to image bounds
            .onTapGesture {
                vm.select(element.id)
                startPosition = element.position
                startScale = element.scale
                startRotation = element.rotation
            }
            // Prepare baseline values when the gesture begins
            .simultaneousGesture(
                drag
                    .onChanged { _ in
                        if vm.selectedElementID != element.id {
                            vm.select(element.id)
                        }
                    }
            )
            .simultaneousGesture(
                magnify.onChanged { _ in
                    if vm.selectedElementID != element.id {
                        vm.select(element.id)
                    }
                }
            )
            .simultaneousGesture(
                rotate.onChanged { _ in
                    if vm.selectedElementID != element.id {
                        vm.select(element.id)
                    }
                }
            )
            .onAppear {
                startPosition = element.position
                startScale = element.scale
                startRotation = element.rotation
            }
    }

    // Keep center point within canvas bounds for a simple clamp
    private func clampToCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: max(0, min(canvasSize.width, p.x)),
                y: max(0, min(canvasSize.height, p.y)))
    }
}

// MARK: - Collage View

struct CollageView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var vm = CollageViewModel()

    // Fetch all Items (filter to those with a primary photo when building grid)
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    ) private var items: FetchedResults<Item>

    private let gridCols = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3)

    var body: some View {
        GeometryReader { geo in
            let halfHeight = geo.size.height / 2.0
            let canvasSide = min(geo.size.width, halfHeight)

            VStack(spacing: 0) {

                // TOP: 1:1 Canvas Area
                ZStack {
                    // Center a square canvas within the top half
                    Color(uiColor: .secondarySystemBackground)
                        .overlay(
                            CanvasLayer(vm: vm, canvasSize: CGSize(width: canvasSide, height: canvasSide))
                                .frame(width: canvasSide, height: canvasSide)
                                .clipped()
                        )
                }
                .frame(height: halfHeight)
                .contentShape(Rectangle())

                // BOTTOM: 3-column grid of primary photos
                ScrollView {
                    LazyVGrid(columns: gridCols, spacing: 8) {
                        ForEach(primaryPhotoItems(), id: \.objectID) { item in
                            let thumb = thumbForPrimary(of: item)
                            Button {
                                vm.add(item: item, in: CGSize(width: canvasSide, height: canvasSide))
                            } label: {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: (halfHeight - 16) / 3)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Add item to canvas"))
                        }
                    }
                    .padding(8)
                }

                .frame(height: halfHeight)
                .background(Color(uiColor: .systemBackground))
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Helpers
    // Returns a NON-optional image, falling back to a system placeholder.
    private func thumbForPrimary(of item: Item) -> UIImage {
        uiImage(from: item) ?? UIImage(systemName: "photo")!
    }

    // If you still want to filter the grid, you can include all items since a fallback always exists.
    private func primaryPhotoItems() -> [Item] {
        Array(items)
    }

    // Unified loader that looks for primary Photo, then item.image; returns nil if neither exists.
    private func uiImage(from item: Item) -> UIImage? {
        if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
           let data = primaryPhoto.data,
           let img = UIImage(data: data) {
            return img
        } else if let fallbackData = item.value(forKey: "image") as? Data,
                  let img = UIImage(data: fallbackData) {
            return img
        } else {
            return nil
        }
    }


}

// MARK: - Canvas Layer

private struct CanvasLayer: View {
    @ObservedObject var vm: CollageViewModel
    let canvasSize: CGSize

    var body: some View {
        ZStack {
            // Simple neutral canvas background
            Rectangle()
                .fill(.thinMaterial)
                .overlay(
                    // Subtle grid to aid alignment (kept minimal; not “additional functionality”)
                    CanvasGrid()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )

            // Elements
            ForEach(vm.elements) { element in
                CanvasItemView2(vm: vm, element: element, canvasSize: canvasSize)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// Lightweight grid path (purely visual aid)
private struct CanvasGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step: CGFloat = max(20, min(rect.width, rect.height) / 10.0)
        stride(from: rect.minX, through: rect.maxX, by: step).forEach { x in
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        stride(from: rect.minY, through: rect.maxY, by: step).forEach { y in
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}
/*
// MARK: - CollageView (Two‑pane)
// Top: interactive square canvas
// Bottom: 3‑column grid of closet items (primary photo per Item)
// Selection behavior (Canva‑style):
//  • Newly added element becomes selected.
//  • Tap on any element selects it and brings it to front.
//  • Tap on blank canvas deselects.
//  • Gestures (drag / pinch / rotate) only hit inside the element’s 1:1 square.

struct CollageView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Canvas state
    @State private var canvas = CanvasState()
    @State private var undoMgr = UndoManagerProxy()

    // 3 equal-width columns
    private let gridCols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 12) {
            CollageCanvasView(canvas: $canvas, undoMgr: undoMgr)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal)

            Divider()

            // Bottom grid of closet items (primary photo per Item)
            ScrollView {
                LazyVGrid(columns: gridCols, spacing: 8) {
                    ForEach(fetchAllItems(), id: \.objectID) { item in
                        ItemCell(image: uiImage(from: item))
                            .onTapGesture { addToCanvas(item) }
                        }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Add to Canvas (select newly added)
    private func addToCanvas(_ item: Item) {
        // Prefer the item's primary photo; else make a placeholder element
        if let primary = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
           let data = primary.data, let img = UIImage(data: data) {
            addElement(photoID: primary.objectID, itemID: item.objectID, seed: img)
        } else if let fallbackData = item.image, let img = UIImage(data: fallbackData) {
            addElement(photoID: nil, itemID: item.objectID, seed: img)
        } else {
            let placeholder = makePlaceholderUIImage()
            addElement(photoID: nil, itemID: item.objectID, seed: placeholder)
        }
    }

    private func addElement(photoID: NSManagedObjectID?, itemID: NSManagedObjectID, seed: UIImage) {
        var element = CanvasElement(photoID: photoID, itemID: itemID)
        let baseSize: CGFloat = 160
        let offset = CGFloat((canvas.elements.count % 5) * 8)
        let pos = CGPoint(x: 0.5 + (offset/600), y: 0.5 + (offset/850)) // normalized
        element.size = CGSize(width: baseSize, height: baseSize)
        element.normalizedCenter = pos
        element.runtimeThumb = seed.downsampled(to: CGSize(width: 200, height: 200))
        element.runtimeImage = seed
        let newID = element.id

        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            undoMgr.register(before: canvas.elements) { newValue in canvas.elements = newValue }
            canvas.elements.append(element)        // appended == topmost
            canvas.selectedID = newID              // select the newly added element
        }
    }
}

// MARK: - ItemCell (square thumbnail)
private struct ItemCell: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.08))
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - CollageCanvasView (square stage + tap‑to‑deselect)
struct CollageCanvasView: View {
    @Binding var canvas: CanvasState
    var undoMgr: UndoManagerProxy

    @State private var stageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Canvas boundary
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    .background(Color.clear)
                    .allowsHitTesting(false)

                // Elements
                ForEach($canvas.elements) { $element in
                    CanvasElementView(
                        element: $element,
                        stageSize: stageSize,
                        allElements: $canvas.elements,
                        selection: $canvas.selectedID,
                        undoMgr: undoMgr
                    )
                }
            }
            .contentShape(Rectangle())                // define canvas hit region
            .onTapGesture {                           // tap blank canvas -> deselect
                canvas.selectedID = nil
            }
            .onChange(of: geo.size) { stageSize = $0 }
            .onAppear { stageSize = geo.size }
        }
    }
}

// MARK: - CanvasElementView (square-only hit area; bring-to-front on interact)
struct CanvasElementView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @Binding var element: CanvasElement
    let stageSize: CGSize
    @Binding var allElements: [CanvasElement]
    @Binding var selection: UUID?
    var undoMgr: UndoManagerProxy

    @State private var liveScale: CGFloat = 1
    @State private var liveRotation: Angle = .zero
    @State private var liveOffset: CGSize = .zero
    @State private var liftedForInteraction = false

    private var frame: CGRect { element.frame(in: stageSize) }

    // Array position as z-index so last is topmost
    private var zOrder: Double {
        Double(allElements.firstIndex(where: { $0.id == element.id }) ?? 0)
    }

    var body: some View {
        // Visual content (image or placeholder)
        let content = ZStack {
            if let uiImage = element.runtimeImage {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else if let thumb = element.runtimeThumb {
                Image(uiImage: thumb).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.secondary.opacity(0.08))
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipped()
       // .overlay(alignment: .center) { selectionRing.allowHitTesting(false) }

        // Container applies transforms
        ZStack { content }
            .frame(width: frame.width, height: frame.height) // keep hit area == square
            .position(x: frame.midX + liveOffset.width, y: frame.midY + liveOffset.height)
            .rotationEffect(element.rotation + liveRotation)
            .scaleEffect(liveScale)
            .zIndex(zOrder)
            // Strict hit area: 1:1 square only
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: frame.width, height: frame.height)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded {
                        selectAndLift()
                       
                    })
                    .simultaneousGesture(
                        dragGesture
                            .simultaneously(with: pinchGesture)
                            .simultaneously(with: rotateGesture)
                    )
            }
            .onAppear { loadImagesIfNeeded() }
    }

    private var selectionRing: some View {
        Group {
            if selection == element.id {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.6), lineWidth: 2)
            }
        }
    }

    // MARK: Gestures
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                selectAndLift()
                liveOffset = value.translation
            }
            .onEnded { value in
                let newCenter = CGPoint(x: frame.midX + value.translation.width,
                                        y: frame.midY + value.translation.height)
                commitCenter(newCenter)
                liveOffset = .zero
                liftedForInteraction = false
                
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { s in
                selectAndLift()
                liveScale = s
            }
            .onEnded { s in
                commitScale(s)
                liveScale = 1
                liftedForInteraction = false
                
            }
    }

    private var rotateGesture: some Gesture {
        RotationGesture()
            .onChanged { a in
                selectAndLift()
                liveRotation = a
            }
            .onEnded { a in
                commitRotation(a)
                liveRotation = .zero
                liftedForInteraction = false
               
            }
    }

    // MARK: Selection / Z-order
    private func selectAndLift() {
        selection = element.id                     // select by element UUID
        guard !liftedForInteraction else { return }
        if let idx = allElements.firstIndex(where: { $0.id == element.id }),
           idx != allElements.count - 1 {
            let e = allElements.remove(at: idx)
            allElements.append(e)                  // bring to front (topmost)
        }
        liftedForInteraction = true
    }

    // MARK: Commit helpers
    private func commitCenter(_ point: CGPoint) {
        let clamped = CGRect(origin: .zero, size: stageSize)
            .insetBy(dx: element.size.width/2, dy: element.size.height/2)
        let nx = max(clamped.minX, min(point.x, clamped.maxX)) / stageSize.width
        let ny = max(clamped.minY, min(point.y, clamped.maxY)) / stageSize.height
        registerUndo()
        element.normalizedCenter = CGPoint(x: nx, y: ny)
    }

    private func commitScale(_ scale: CGFloat) {
        registerUndo()
        element.size = CGSize(width: element.size.width * scale, height: element.size.height * scale)
    }

    private func commitRotation(_ angle: Angle) {
        registerUndo()
        element.rotation = element.rotation + angle
    }

    private func registerUndo() {
        undoMgr.register(before: allElements) { newValue in allElements = newValue }
    }

    // MARK: Image Loading
    private func loadImagesIfNeeded() {
        if element.photoID == nil { return }            // placeholder-only element
        if element.runtimeThumb == nil {
            if let thumb = element.loadThumbnail(context: viewContext) { element.runtimeThumb = thumb }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if let full = element.loadFullRes(context: viewContext) {
                DispatchQueue.main.async {
                    withAnimation(.easeIn(duration: 0.15)) { element.runtimeImage = full }
                }
            }
        }
    }
}

// MARK: - Models & Helpers
struct CanvasState: Equatable {
    var elements: [CanvasElement] = []
    var selectedID: UUID? = nil                   // central selection
    var featuredItemIDs: [NSManagedObjectID] {
        Array(Set(elements.compactMap { $0.itemID }))
    }
}

struct CanvasElement: Identifiable, Equatable {
    let id = UUID()
    let photoID: NSManagedObjectID?               // nil = placeholder element
    let itemID: NSManagedObjectID?

    // Layout
    var normalizedCenter: CGPoint = CGPoint(x: 0.5, y: 0.5) // 0..1
    var size: CGSize = CGSize(width: 160, height: 160)
    var rotation: Angle = .zero

    // Runtime images (not persisted)
    var runtimeThumb: UIImage? = nil
    var runtimeImage: UIImage? = nil

    // Frame in a given stage size (pre-rotation)
    func frame(in stage: CGSize) -> CGRect {
        let x = normalizedCenter.x * stage.width
        let y = normalizedCenter.y * stage.height
        return CGRect(x: x - size.width/2, y: y - size.height/2, width: size.width, height: size.height)
    }

    // Core Data image loads
    func loadThumbnail(context: NSManagedObjectContext?) -> UIImage? { loadImage(context: context, thumb: true) }
    func loadFullRes(context: NSManagedObjectContext?) -> UIImage? { loadImage(context: context, thumb: false) }

    private func loadImage(context: NSManagedObjectContext?, thumb: Bool) -> UIImage? {
        guard let ctx = context, let photoID else { return nil }
        do {
            let photo = try ctx.existingObject(with: photoID) as? Photo
            guard let data = photo?.data, let img = UIImage(data: data) else { return nil }
            return thumb ? img.downsampled(to: CGSize(width: 200, height: 200)) : img
        } catch { return nil }
    }
}

// Simple undo/redo for the elements array
final class UndoManagerProxy {
    private var undoStack: [[CanvasElement]] = []
    private var redoStack: [[CanvasElement]] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func register(before state: [CanvasElement], apply: @escaping ([CanvasElement]) -> Void) {
        undoStack.append(state)
        redoStack.removeAll()
    }
    func undo(current: inout [CanvasElement]) {
        guard let prev = undoStack.popLast() else { return }
        let now = current
        current = prev
        redoStack.append(now)
    }
    func redo(current: inout [CanvasElement]) {
        guard let next = redoStack.popLast() else { return }
        let now = current
        current = next
        undoStack.append(now)
    }
}

// MARK: - Image helpers (grid rendering + placeholder)
private extension CollageView {
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

    func makePlaceholderUIImage(side: CGFloat = 512) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            let cfg = UIImage.SymbolConfiguration(pointSize: side * 0.35, weight: .regular)
            let symbol = UIImage(systemName: "photo", withConfiguration: cfg)?
                .withTintColor(UIColor.secondaryLabel, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: side*0.175, y: side*0.175, width: side*0.65, height: side*0.65))
        }
    }
}

// MARK: - Data Fetching (Items)
private extension CollageView {
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
}

// MARK: - UIImage downsampling
extension UIImage {
    func downsampled(to targetSize: CGSize, scale: CGFloat = UIScreen.main.scale) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: targetSize)) }
    }
}

*/*/
