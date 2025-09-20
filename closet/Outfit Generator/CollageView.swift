import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - CollageView
// Two-pane layout: square canvas on top, photo grid below. Tap a grid cell to add to canvas with animation.
// Drag/Pinch/Rotate on-canvas items with snapping to canvas center/edges and other items. Undo/Redo in toolbar.
// Thumbnails in grid; full‑res swapped in after drop. Export transparent PNG. Contextual first‑time hints.

// NOTE: This file assumes Core Data entities `Item` and `Photo` exist.
// `Item` has to-many `photos: Set<Photo>` (or [Photo]) and identifying fields like `id: UUID`, `timestamp: Date`, `isWishlist: Bool`.
// `Photo` owns the image data (`imageData: Data`), and a to-one back-reference to its `Item`.
// You can rename properties to match your schema—look for TODO markers.

struct CollageView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    // MARK: Inputs & Filters (customize these bindings as needed)
    @State private var filterText: String = ""
    @State private var showFavoritesOnly: Bool = false
    
    // MARK: Canvas State
    @State private var canvas = CanvasState()
    @State private var undoMgr = UndoManagerProxy()
    @AppStorage("hasSeenCollageHints") private var hasSeenHints: Bool = false
    
    // MARK: Export
    @State private var isExporting: Bool = false
    @State private var exportImage: UIImage? = nil
    
    // MARK: Fetch Items/Photos (lightweight)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
        animation: .default
    ) private var items: FetchedResults<Item>
    
    // MARK: Grid Layout
    private let gridCols = [
        GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 8)
    ]
    
    // MARK: Body
    var body: some View {
        VStack(spacing: 12) {
            // Square canvas honoring transparent export
            CollageCanvasView(canvas: $canvas, undoMgr: undoMgr)
                .aspectRatio(1, contentMode: .fit)
                .background(Color.clear)
                .overlay(alignment: .topLeading) { hintsOverlay }
                .padding(.horizontal)
                .animation(.spring(response: 0.28, dampingFraction: 0.9), value: canvas.elements)
            
            Divider()
            
            // Asset browser (bottom grid)
            assetBrowser
        }
        .toolbar { toolbarContent }
        .onAppear { if !hasSeenHints { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { hasSeenHints = true } } }
        .sheet(isPresented: $isExporting) { exportPreviewSheet }
    }
}

// MARK: - Asset Browser (Grid)
extension CollageView {
    private var assetBrowser: some View {
        VStack(spacing: 8) {
            // Quick filters row (extend as needed)
            HStack(spacing: 8) {
                TextField("Search…", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Favs", isOn: $showFavoritesOnly)
                    .toggleStyle(.switch)
            }
            .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: gridCols, spacing: 8) {
                    ForEach(filteredPhotos(), id: \.objectID) { photo in
                        PhotoGridCell(photo: photo)
                            .onTapGesture { onSelect(photo) }
                            .contextMenu { contextMenu(for: photo) }
                            .sensoryFeedback(.selection, trigger: canvas.elements.count) // Light tick on add
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func filteredPhotos() -> [Photo] {
        var result: [Photo] = []
        for item in items {
            // TODO: adjust if your relationship is optional/ordered
            let photos = (item.photos as? Set<Photo>)?.sorted(by: { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }) ?? []
            for p in photos {
                // Example favorite flag—replace with your field if present
                if showFavoritesOnly, (p.isFavorite == false) { continue }
                if !filterText.isEmpty {
                    let name = (p.caption ?? "") + (item.name ?? "")
                    if !name.localizedCaseInsensitiveContains(filterText) { continue }
                }
                result.append(p)
            }
        }
        return result
    }
    
    @ViewBuilder
    private func contextMenu(for photo: Photo) -> some View {
        Button { onSelect(photo) } label: { Label("Add to Canvas", systemImage: "plus") }
        Button { toggleFavorite(photo) } label: { Label("Favorite", systemImage: "star") }
    }
    
    private func toggleFavorite(_ photo: Photo) {
        // Replace with your schema
        viewContext.perform {
            photo.isFavorite.toggle()
            try? viewContext.save()
        }
    }
}

// MARK: - Canvas Interactions
extension CollageView {
    private func onSelect(_ photo: Photo) {
        // Create element with thumbnail first, then silently swap to full‑res
        let element = CanvasElement(photoID: photo.objectID, itemID: photo.item?.objectID, frame: .zero)
        
        // Auto-placement: center with slight offset if elements exist
        let baseSize: CGFloat = 160
        let offset = CGFloat((canvas.elements.count % 5) * 8)
        let pos = CGPoint(x: 0.5 + (offset/600), y: 0.5 + (offset/850)) // normalized
        var placed = element
        placed.size = CGSize(width: baseSize, height: baseSize)
        placed.normalizedCenter = pos
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            undoMgr.register(before: canvas.elements) { newValue in canvas.elements = newValue }
            canvas.elements.append(placed)
        }
        
        // Haptic success
        Haptics.success()
    }
}

// MARK: - Toolbar (Undo/Redo, Export)
extension CollageView {
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { undoMgr.undo(current: &canvas.elements) } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!undoMgr.canUndo)
            Button { undoMgr.redo(current: &canvas.elements) } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!undoMgr.canRedo)
            Button { exportCollage() } label: { Image(systemName: "square.and.arrow.up") }
        }
    }
    
    private var exportPreviewSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                if let img = exportImage { Image(uiImage: img).resizable().interpolation(.high).scaledToFit() }
                Text("Transparent PNG • 1:1")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Export Preview")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { isExporting = false } }
            }
        }
    }
    
    private func exportCollage() {
        let renderer = CollageRenderer()
        let image = renderer.renderPNG(from: canvas)
        self.exportImage = image
        self.isExporting = true
        // TODO: persist as new Item if desired; provide a hook to caller.
    }
}

// MARK: - Hints Overlay
extension CollageView {
    private var hintsOverlay: some View {
        Group {
            if !hasSeenHints && canvas.elements.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tap a photo below to add it here", systemImage: "hand.tap")
                    Label("Drag to move • Pinch to resize • Rotate with two fingers", systemImage: "arrow.2.squarepath")
                    Label("Use Undo/Redo from the top-right", systemImage: "arrow.uturn.backward")
                }
                .font(.footnote)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(8)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - CollageCanvasView (Square stage)
struct CollageCanvasView: View {
    @Binding var canvas: CanvasState
    var undoMgr: UndoManagerProxy
    
    @State private var stageSize: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Transparent background; outline to indicate bounds
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    .background(Color.clear)
                
                // Elements
                ForEach($canvas.elements) { $element in
                    CanvasElementView(element: $element, stageSize: stageSize, allElements: $canvas.elements, undoMgr: undoMgr)
                }
            }
            .onChange(of: geo.size) { stageSize = geo.size }
            .onAppear { stageSize = geo.size }
        }
    }
}

// MARK: - CanvasElementView (Drag/Pinch/Rotate + Snapping)
struct CanvasElementView: View {
    @Binding var element: CanvasElement
    let stageSize: CGSize
    @Binding var allElements: [CanvasElement]
    var undoMgr: UndoManagerProxy
    
    @State private var isActive: Bool = false
    @State private var liveScale: CGFloat = 1
    @State private var liveRotation: Angle = .zero
    @State private var liveOffset: CGSize = .zero
    @State private var snapGuides: [Guide] = []
    
    private var frame: CGRect { element.frame(in: stageSize) }
    
    var body: some View {
        ZStack {
            if let uiImage = element.runtimeImage { Image(uiImage: uiImage).resizable().scaledToFill() } else { elementImage }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX + liveOffset.width, y: frame.midY + liveOffset.height)
        .rotationEffect(element.rotation + liveRotation)
        .scaleEffect(liveScale)
        .clipped()
        .contentShape(Rectangle())
        .overlay(alignment: .center) { selectionRing }
        .gesture(dragGesture.simultaneously(with: pinchGesture).simultaneously(with: rotateGesture))
        .onTapGesture { isActive = true }
        .onChange(of: isActive) { _ in Haptics.selection() }
        .onAppear { loadImagesIfNeeded() }
        .overlay(alignment: .center) { SnapGuideOverlay(guides: snapGuides, stage: stageSize) }
        .onChange(of: liveOffset) { _ in updateSnapGuides() }
        .onChange(of: element) { _ in updateSnapGuides() }
    }
    
    // Placeholder -> actual image loader
    @ViewBuilder private var elementImage: some View {
        if let thumb = element.runtimeThumb { Image(uiImage: thumb).resizable().scaledToFill() }
        else { Rectangle().fill(Color.secondary.opacity(0.08)) }
    }
    
    private var selectionRing: some View {
        Group {
            if isActive {
                RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.6), lineWidth: 2)
            }
        }
    }
    
    // MARK: Gestures
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                isActive = true
                liveOffset = value.translation
                updateSnapGuides(with: value.translation)
            }
            .onEnded { value in
                let newCenter = CGPoint(x: frame.midX + value.translation.width, y: frame.midY + value.translation.height)
                commitCenter(newCenter)
                liveOffset = .zero
                Haptics.light()
            }
    }
    
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { s in
                isActive = true
                liveScale = s
            }
            .onEnded { s in
                commitScale(s)
                liveScale = 1
                Haptics.light()
            }
    }
    
    private var rotateGesture: some Gesture {
        RotationGesture()
            .onChanged { a in
                isActive = true
                liveRotation = a
            }
            .onEnded { a in
                commitRotation(a)
                liveRotation = .zero
                Haptics.light()
            }
    }
    
    // MARK: Commit helpers
    private func commitCenter(_ point: CGPoint) {
        let clamped = CGRect(origin: .zero, size: stageSize).insetBy(dx: element.size.width/2, dy: element.size.height/2)
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
    
    // MARK: Snap Guides
    private func updateSnapGuides(with translation: CGSize = .zero) {
        var guides: [Guide] = []
        let movingFrame = frame.offsetBy(dx: translation.width, dy: translation.height)
        let stageRect = CGRect(origin: .zero, size: stageSize)
        
        // Stage center & edges
        let stageCenter = CGPoint(x: stageRect.midX, y: stageRect.midY)
        if abs(movingFrame.midX - stageCenter.x) < 8 { guides.append(.v(stageCenter.x)) }
        if abs(movingFrame.midY - stageCenter.y) < 8 { guides.append(.h(stageCenter.y)) }
        if abs(movingFrame.minX - stageRect.minX) < 8 { guides.append(.v(stageRect.minX)) }
        if abs(movingFrame.maxX - stageRect.maxX) < 8 { guides.append(.v(stageRect.maxX)) }
        if abs(movingFrame.minY - stageRect.minY) < 8 { guides.append(.h(stageRect.minY)) }
        if abs(movingFrame.maxY - stageRect.maxY) < 8 { guides.append(.h(stageRect.maxY)) }
        
        // Other elements centers (simple example)
        for other in allElements where other.id != element.id {
            let of = other.frame(in: stageSize)
            if abs(movingFrame.midX - of.midX) < 8 { guides.append(.v(of.midX)) }
            if abs(movingFrame.midY - of.midY) < 8 { guides.append(.h(of.midY)) }
        }
        
        snapGuides = guides
    }
    
    // MARK: Image Loading
    private func loadImagesIfNeeded() {
        // Attempt to load thumb immediately, then swap to full‑res
        if element.runtimeThumb == nil {
            if let thumb = element.loadThumbnail(context: element.managedObjectContext) { element.runtimeThumb = thumb }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if let full = element.loadFullRes(context: element.managedObjectContext) {
                DispatchQueue.main.async { withAnimation(.easeIn(duration: 0.15)) { element.runtimeImage = full } }
            }
        }
    }
}

// MARK: - Snap Guide Overlay
struct SnapGuideOverlay: View {
    let guides: [Guide]
    let stage: CGSize
    var body: some View {
        ZStack {
            ForEach(guides) { g in
                switch g.kind {
                case .h(let y): Rectangle().frame(width: stage.width, height: 1).position(x: stage.width/2, y: y).foregroundStyle(Color.blue.opacity(0.45))
                case .v(let x): Rectangle().frame(width: 1, height: stage.height).position(x: x, y: stage.height/2).foregroundStyle(Color.blue.opacity(0.45))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Models & Helpers
struct CanvasState: Equatable {
    var elements: [CanvasElement] = []
    var featuredItemIDs: [NSManagedObjectID] {
        Array(Set(elements.compactMap { $0.itemID }))
    }
}

struct CanvasElement: Identifiable, Equatable {
    let id = UUID()
    let photoID: NSManagedObjectID
    let itemID: NSManagedObjectID?
    
    // Layout
    var normalizedCenter: CGPoint = CGPoint(x: 0.5, y: 0.5) // 0..1
    var size: CGSize = CGSize(width: 160, height: 160)
    var rotation: Angle = .zero
    
    // Runtime images (not persisted)
    var runtimeThumb: UIImage? = nil
    var runtimeImage: UIImage? = nil
    
    // MARK: Frame helpers
    func frame(in stage: CGSize) -> CGRect {
        let x = normalizedCenter.x * stage.width
        let y = normalizedCenter.y * stage.height
        return CGRect(x: x - size.width/2, y: y - size.height/2, width: size.width, height: size.height)
    }
    
    // MARK: Image Loads
    var managedObjectContext: NSManagedObjectContext? { (UIApplication.shared.delegate as? AppDelegate)?.persistentContainer.viewContext }
    
    func loadThumbnail(context: NSManagedObjectContext?) -> UIImage? { loadImage(context: context, thumb: true) }
    func loadFullRes(context: NSManagedObjectContext?) -> UIImage? { loadImage(context: context, thumb: false) }
    
    private func loadImage(context: NSManagedObjectContext?, thumb: Bool) -> UIImage? {
        guard let ctx = context else { return nil }
        do {
            let photo = try ctx.existingObject(with: photoID) as? Photo
            guard let data = photo?.imageData, let img = UIImage(data: data) else { return nil }
            if thumb { return img.downsampled(to: CGSize(width: 200, height: 200)) }
            return img
        } catch { return nil }
    }
}

enum GuideKind: Equatable { case h(CGFloat), v(CGFloat) }
struct Guide: Identifiable, Equatable { let id = UUID(); let kind: GuideKind; static func h(_ y: CGFloat) -> Guide { .init(kind: .h(y)) }; static func v(_ x: CGFloat) -> Guide { .init(kind: .v(x)) } }

// Simple undo/redo for the elements array
final class UndoManagerProxy {
    private var undoStack: [[CanvasElement]] = []
    private var redoStack: [[CanvasElement]] = []
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    
    func register(before state: [CanvasElement], apply: @escaping ([CanvasElement]) -> Void) {
        undoStack.append(state)
        redoStack.removeAll()
        // When a new change occurs, `apply` is used in undo(). We store closure? Keep simple: only store states.
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

// MARK: - Renderer (Transparent PNG, 1:1)
final class CollageRenderer {
    func renderPNG(from canvas: CanvasState, size: CGSize = CGSize(width: 2048, height: 2048)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.clear.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for element in canvas.elements {
                guard let image = element.runtimeImage ?? element.runtimeThumb else { continue }
                let frame = element.frame(in: size)
                let cg = image.cgImage!
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: frame.midX, y: frame.midY)
                ctx.cgContext.rotate(by: CGFloat(element.rotation.radians))
                ctx.cgContext.translateBy(x: -frame.midX, y: -frame.midY)
                UIImage(cgImage: cg).draw(in: frame)
                ctx.cgContext.restoreGState()
            }
        }
        return image
    }
}

// MARK: - Photo Grid Cell (Thumbnail-only)
struct PhotoGridCell: View {
    let photo: Photo
    @State private var thumb: UIImage? = nil
    
    var body: some View {
        ZStack {
            if let img = thumb { Image(uiImage: img).resizable().interpolation(.medium).scaledToFill() }
            else { Rectangle().fill(Color.secondary.opacity(0.08)) }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 1) }
        .task { await loadThumb() }
        .accessibilityHidden(true)
    }
    
    private func loadThumb() async {
        if let data = photo.imageData, let ui = UIImage(data: data)?.downsampled(to: CGSize(width: 200, height: 200)) {
            thumb = ui
        }
    }
}

// MARK: - Haptics helper
enum Haptics {
    static func success() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
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

// MARK: - DEBUG stubs (Remove/replace with your AppDelegate container)
#if DEBUG
final class AppDelegate: NSObject, UIApplicationDelegate {
    let persistentContainer = NSPersistentContainer(name: "Model")
}
#endif
