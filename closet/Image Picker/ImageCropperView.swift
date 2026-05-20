//
//  ImageCropperView.swift
//  closet
//
//  Created by Dan Warner on 8/13/25.
//

import SwiftUI
import PhotosUI
import UIKit

import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

struct ImageCropperView: View {
    let originalImage: UIImage
    let onCrop: (UIImage) -> Void
    let isEditing: Bool // true when editing existing image, false when adding new
    /// When non-`nil`, Cancel calls this instead of `dismiss()` (e.g. queue flows with confirmation).
    let onCancel: (() -> Void)?

    // The image currently shown/edited
    @State private var currentImage: UIImage
    /// Linear history for undo/redo (background removal, erase, repaint).
    @State private var editHistory: [EditSnapshot]
    @State private var editHistoryIndex: Int
    // Transform state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero // Track the offset at the start of drag
    @State private var isDragging: Bool = false // Track if we're currently dragging

    @State private var cropViewSize: CGSize = .zero

    @State private var isProcessingBackgroundRemoval = false
    @State private var hasBackgroundRemoved = false

    // Erase / restore brush — strokes in image coordinates relative to `eraseSourceImage`
    @State private var isErasing: Bool = false
    @State private var isRestoringBrush: Bool = false
    @State private var eraseSourceImage: UIImage?
    @State private var brushEditOps: [BrushEditOperation] = []
    @State private var activeEraseStroke: BrushStroke?
    @State private var activeRestoreStroke: BrushStroke?
    @State private var hasEraseEdits: Bool = false
    @State private var brushSize: CGFloat = 30.0
    @State private var lastErasePoint: CGPoint?

    private static let maxBrushSize: CGFloat = 100
    private static let cropChromeBackground = Color(white: 0.8)
    private static let bottomToolbarHeight: CGFloat = 0

    @State private var bottomSafeInset: CGFloat = 0

    private struct BottomSafeAreaInsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private struct BrushStroke: Equatable {
        var points: [CGPoint]
        var brushDiameter: CGFloat
    }

    private enum BrushEditOperation: Equatable {
        case erase(BrushStroke)
        case restore(BrushStroke)
    }

    private struct EditSnapshot {
        var currentImage: UIImage
        var eraseSourceImage: UIImage?
        var brushEditOps: [BrushEditOperation]
        var hasBackgroundRemoved: Bool
    }

    private var isBrushEditing: Bool { isErasing || isRestoringBrush }
    private var canUndoEdit: Bool { editHistoryIndex > 0 }
    private var canRedoEdit: Bool { editHistoryIndex < editHistory.count - 1 }
    private var isRepaintDisabled: Bool {
        isProcessingBackgroundRemoval || (!hasEraseEdits && !isBrushEditing)
    }

    @Environment(\.dismiss) private var dismiss
    
    init(
        originalImage: UIImage,
        onCrop: @escaping (UIImage) -> Void,
        isEditing: Bool = false,
        onCancel: (() -> Void)? = nil
    ) {
        self.originalImage = originalImage
        self.onCrop = onCrop
        self.isEditing = isEditing
        self.onCancel = onCancel
        _currentImage = State(initialValue: originalImage)
        let initialSnapshot = EditSnapshot(
            currentImage: originalImage,
            eraseSourceImage: nil,
            brushEditOps: [],
            hasBackgroundRemoved: false
        )
        _editHistory = State(initialValue: [initialSnapshot])
        _editHistoryIndex = State(initialValue: 0)
    }

    var body: some View {
        ZStack {
                Self.cropChromeBackground

                GeometryReader { geo in
                    let actionBarHeight: CGFloat = 52
                    let side = min(geo.size.width, max(0, geo.size.height - actionBarHeight))
                    
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            
                            ZStack {
                                cropTransparencyCheckerboard(side: side)
                                cropImageLayer(side: side)
                            }
                            .frame(width: side, height: side)
                            .contentShape(Rectangle())
                            .highPriorityGesture(brushDragGesture(side: side), including: isBrushEditing ? .all : .subviews)
                            .frame(width: side, height: side)
                            .onAppear {
                                cropViewSize = CGSize(width: side, height: side)
                            }
                            .onChange(of: geo.size) { newSize in
                                let s = min(newSize.width, max(0, newSize.height - actionBarHeight))
                                cropViewSize = CGSize(width: s, height: s)
                            }
                            
                            Spacer(minLength: 0)
                        }
                        Divider()
                        cropEditActionsRow
                            .frame(width: side)

                        Spacer(minLength: 0)
                    }
                }

                if isProcessingBackgroundRemoval {
                    ProgressView("Removing background…")
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.35))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Crop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if let onCancel {
                        onCancel()
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 24) {
                    HStack(spacing: 24) {
                        Button {
                            toggleEraseMode()
                        } label: {
                            cropToolLabel(icon: "eraser", title: "Erase", isActive: isErasing)
                        }
                        .disabled(isProcessingBackgroundRemoval)
                        .accessibilityLabel(isErasing ? "Erase mode on" : "Erase")

                        Button {
                            toggleRestoreBrushMode()
                        } label: {
                            cropToolLabel(
                                icon: "paintbrush",
                                title: "Repaint",
                                isActive: isRestoringBrush,
                                tint: repaintToolTint
                            )
                        }
                        .disabled(isRepaintDisabled)
                        .accessibilityLabel(isRestoringBrush ? "Repaint mode on" : "Repaint")
                    }

                    Spacer(minLength: 12)

                    Button {
                        restoreErase()
                    } label: {
                        cropToolLabel(icon: "arrow.counterclockwise", title: "Restore", tint: .red)
                    }
                    .disabled(isProcessingBackgroundRemoval || !hasEraseEdits)
                    .accessibilityLabel("Restore all erased areas")
                }
                .frame(maxWidth: .infinity)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") {
                    cropAndSaveImage()
                }
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: BottomSafeAreaInsetKey.self,
                    value: geo.safeAreaInsets.bottom
                )
            }
        }
        .onPreferenceChange(BottomSafeAreaInsetKey.self) { bottomSafeInset = $0 }
        .overlay(alignment: .bottom) {
            if isBrushEditing {
                brushSizeSliderBar
                    .padding(.bottom, Self.bottomToolbarHeight + bottomSafeInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Size control for erase and repaint (only one brush mode active at a time).
    private var brushSizeSliderBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Text("Size")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(
                    value: $brushSize,
                    in: 1...Self.maxBrushSize,
                    step: 1
                )
                Text("\(Int(brushSize.rounded()))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    /// Icon action row directly under the crop square (matches `SocialEngagementActionsRow` on item detail).
    private var cropEditActionsRow: some View {
        HStack(spacing: 24) {
            Button {
                undoEdit()
            } label: {
                cropToolLabel(icon: "arrowshape.turn.up.backward", title: "Undo", isActive: canUndoEdit)
            }
            .buttonStyle(.plain)
            .disabled(isProcessingBackgroundRemoval || !canUndoEdit)
            .accessibilityLabel("Undo")

            Button {
                redoEdit()
            } label: {
                cropToolLabel(icon: "arrowshape.turn.up.forward", title: "Redo", isActive: canRedoEdit)
            }
            .buttonStyle(.plain)
            .disabled(isProcessingBackgroundRemoval || !canRedoEdit)
            .accessibilityLabel("Redo")

            Spacer(minLength: 12)

            Button {
                removeBackground()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .imageScale(.large)
                    Text("Remove Background")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(hasBackgroundRemoved ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessingBackgroundRemoval || hasBackgroundRemoved)
            .accessibilityLabel("Remove Background")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(Color(.systemBackground))
    }

    private var repaintToolTint: Color {
        if isRepaintDisabled { return .secondary }
        if isRestoringBrush { return .accentColor }
        return .primary
    }

    private func cropToolLabel(
        icon: String,
        title: String,
        isActive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .imageScale(.large)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(tint ?? (isActive ? Color.accentColor : .primary))
    }

    private func makeEditSnapshot() -> EditSnapshot {
        EditSnapshot(
            currentImage: currentImage,
            eraseSourceImage: eraseSourceImage,
            brushEditOps: brushEditOps,
            hasBackgroundRemoved: hasBackgroundRemoved
        )
    }

    private func recordEditHistory() {
        let snapshot = makeEditSnapshot()
        if editHistoryIndex < editHistory.count - 1 {
            editHistory.removeSubrange((editHistoryIndex + 1)...)
        }
        if let last = editHistory.last,
           last.brushEditOps == snapshot.brushEditOps,
           last.hasBackgroundRemoved == snapshot.hasBackgroundRemoved,
           last.currentImage === snapshot.currentImage,
           last.eraseSourceImage === snapshot.eraseSourceImage {
            return
        }
        editHistory.append(snapshot)
        editHistoryIndex = editHistory.count - 1
    }

    private func applyEditSnapshot(_ snapshot: EditSnapshot) {
        currentImage = snapshot.currentImage
        eraseSourceImage = snapshot.eraseSourceImage
        brushEditOps = snapshot.brushEditOps
        hasBackgroundRemoved = snapshot.hasBackgroundRemoved
        activeEraseStroke = nil
        activeRestoreStroke = nil
        lastErasePoint = nil
        hasEraseEdits = !brushEditOps.isEmpty
    }

    private func undoEdit() {
        guard canUndoEdit else { return }
        editHistoryIndex -= 1
        applyEditSnapshot(editHistory[editHistoryIndex])
    }

    private func redoEdit() {
        guard canRedoEdit else { return }
        editHistoryIndex += 1
        applyEditSnapshot(editHistory[editHistoryIndex])
    }

// MARK: - Erase Functions

    private func cropTransparencyCheckerboard(side: CGFloat) -> some View {
        Canvas { context, size in
            let tile: CGFloat = 20
            let light = Color(white: 0.92)
            let dark = Color(white: 0.78)
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var col = 0
                var x: CGFloat = 0
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: tile, height: tile)
                    context.fill(
                        Path(rect),
                        with: .color((row + col).isMultiple(of: 2) ? light : dark)
                    )
                    x += tile
                    col += 1
                }
                y += tile
                row += 1
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    /// Renders image with orientation baked in so mask pixels align with on-screen content.
    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    @ViewBuilder
    private func cropImageLayer(side: CGFloat) -> some View {
        let image = Image(uiImage: currentImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: side, height: side)
            .clipped()

        if isBrushEditing {
            image
        } else {
            image
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                lastOffset = offset
                                isDragging = true
                            }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                            isDragging = false
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
        }
    }

    private func brushDragGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isErasing {
                    handleEraseDrag(at: value.location, side: side)
                } else if isRestoringBrush {
                    handleRestoreBrushDrag(at: value.location, side: side)
                }
            }
            .onEnded { _ in
                if isErasing {
                    commitActiveEraseStroke()
                } else if isRestoringBrush {
                    commitActiveRestoreStroke()
                }
            }
    }

    private func clearEraseSession() {
        eraseSourceImage = nil
        brushEditOps = []
        activeEraseStroke = nil
        activeRestoreStroke = nil
        hasEraseEdits = false
        lastErasePoint = nil
    }

    private func beginEraseSessionIfNeeded() {
        if eraseSourceImage == nil {
            eraseSourceImage = normalizedImage(currentImage)
            brushEditOps = []
            activeEraseStroke = nil
            activeRestoreStroke = nil
            hasEraseEdits = false
        }
    }

    private func commitActiveEraseStroke() {
        if let stroke = activeEraseStroke, !stroke.points.isEmpty {
            brushEditOps.append(.erase(stroke))
            recordEditHistory()
        }
        activeEraseStroke = nil
        lastErasePoint = nil
    }

    private func commitActiveRestoreStroke() {
        if let stroke = activeRestoreStroke, !stroke.points.isEmpty {
            brushEditOps.append(.restore(stroke))
            recordEditHistory()
        }
        activeRestoreStroke = nil
        lastErasePoint = nil
    }

    func toggleEraseMode() {
        if isErasing {
            commitActiveEraseStroke()
            isErasing = false
            return
        }
        commitActiveRestoreStroke()
        isRestoringBrush = false
        isErasing = true
        beginEraseSessionIfNeeded()
    }

    func toggleRestoreBrushMode() {
        if isRestoringBrush {
            commitActiveRestoreStroke()
            isRestoringBrush = false
            return
        }
        commitActiveEraseStroke()
        isErasing = false
        isRestoringBrush = true
        beginEraseSessionIfNeeded()
    }

    /// Restores all erased regions while keeping other edits (e.g. background removal).
    func restoreErase() {
        guard let source = eraseSourceImage else { return }
        brushEditOps = []
        activeEraseStroke = nil
        activeRestoreStroke = nil
        hasEraseEdits = false
        lastErasePoint = nil
        currentImage = source
        recordEditHistory()
    }

    func handleEraseDrag(at location: CGPoint, side: CGFloat) {
        beginEraseSessionIfNeeded()
        guard let source = eraseSourceImage else { return }

        let imagePoint = convertToImageCoordinates(touchPoint: location, side: side, imageSize: source.size)
        let brushDiameter = brushDiameterInImagePoints(side: side, imageSize: source.size)

        if activeEraseStroke == nil {
            activeEraseStroke = BrushStroke(points: [imagePoint], brushDiameter: brushDiameter)
        } else {
            activeEraseStroke?.points.append(imagePoint)
            activeEraseStroke?.brushDiameter = brushDiameter
        }

        lastErasePoint = imagePoint
        hasEraseEdits = true
        applyImageEdits()
    }

    func handleRestoreBrushDrag(at location: CGPoint, side: CGFloat) {
        beginEraseSessionIfNeeded()
        guard let source = eraseSourceImage else { return }

        let imagePoint = convertToImageCoordinates(touchPoint: location, side: side, imageSize: source.size)
        let brushDiameter = brushDiameterInImagePoints(side: side, imageSize: source.size)

        if activeRestoreStroke == nil {
            activeRestoreStroke = BrushStroke(points: [imagePoint], brushDiameter: brushDiameter)
        } else {
            activeRestoreStroke?.points.append(imagePoint)
            activeRestoreStroke?.brushDiameter = brushDiameter
        }

        lastErasePoint = imagePoint
        hasEraseEdits = true
        applyImageEdits()
    }

    private func brushDiameterInImagePoints(side: CGFloat, imageSize: CGSize) -> CGFloat {
        let baseScale = max(side / imageSize.width, side / imageSize.height)
        let effectiveScale = baseScale * scale
        guard effectiveScale > 0 else { return brushSize }
        let clampedSize = min(max(brushSize, 1), Self.maxBrushSize)
        return max(1, clampedSize / effectiveScale)
    }

    func convertToImageCoordinates(touchPoint: CGPoint, side: CGFloat, imageSize: CGSize) -> CGPoint {
        let baseScale = max(side / imageSize.width, side / imageSize.height)
        let effectiveScale = baseScale * scale
        let drawnW = imageSize.width * effectiveScale
        let drawnH = imageSize.height * effectiveScale
        let originX = (side - drawnW) / 2 + offset.width
        let originY = (side - drawnH) / 2 + offset.height
        let x = (touchPoint.x - originX) / effectiveScale
        let y = (touchPoint.y - originY) / effectiveScale
        return CGPoint(
            x: max(0, min(imageSize.width, x)),
            y: max(0, min(imageSize.height, y))
        )
    }

    /// Re-renders `eraseSourceImage`, replaying erase and restore operations in chronological order.
    private func applyImageEdits() {
        guard let source = eraseSourceImage else { return }

        var ops = brushEditOps
        if let active = activeEraseStroke, !active.points.isEmpty {
            ops.append(.erase(active))
        } else if let active = activeRestoreStroke, !active.points.isEmpty {
            ops.append(.restore(active))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = source.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: source.size, format: format)
        currentImage = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: source.size)
            source.draw(in: rect)

            for op in ops {
                switch op {
                case .erase(let stroke):
                    cg.setBlendMode(.clear)
                    cg.setFillColor(UIColor.clear.cgColor)
                    cg.setStrokeColor(UIColor.clear.cgColor)
                    cg.setLineCap(.round)
                    cg.setLineJoin(.round)
                    paintClearStroke(stroke, in: cg)
                case .restore(let stroke):
                    cg.setBlendMode(.normal)
                    cg.saveGState()
                    clipToStroke(stroke, in: cg)
                    source.draw(in: rect)
                    cg.restoreGState()
                }
            }
        }
    }

    private func paintClearStroke(_ stroke: BrushStroke, in cg: CGContext) {
        let diameter = stroke.brushDiameter
        let points = stroke.points
        guard !points.isEmpty else { return }

        if points.count == 1, let point = points.first {
            let rect = CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            cg.fillEllipse(in: rect)
            return
        }

        cg.setLineWidth(diameter)
        cg.move(to: points[0])
        for point in points.dropFirst() {
            cg.addLine(to: point)
        }
        cg.strokePath()
    }

    private func clipToStroke(_ stroke: BrushStroke, in cg: CGContext) {
        let diameter = stroke.brushDiameter
        let points = stroke.points
        guard !points.isEmpty else { return }

        if points.count == 1, let point = points.first {
            let rect = CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            cg.addEllipse(in: rect)
            cg.clip()
            return
        }

        cg.setLineWidth(diameter)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.move(to: points[0])
        for point in points.dropFirst() {
            cg.addLine(to: point)
        }
        cg.replacePathWithStrokedPath()
        cg.clip()
    }
// MARK: Remove Background by Vision
    
    func removeBackground(borderWidth: Float = 1.0) {
        guard let ciInput = CIImage(image: currentImage) else {
            print("Failed to create CIImage")
            return
        }

        isProcessingBackgroundRemoval = true

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: ciInput)

            do {
                try handler.perform([request])
                guard let result = request.results?.first else {
                    print("No results from mask request")
                    DispatchQueue.main.async { isProcessingBackgroundRemoval = false }
                    return
                }

                guard let maskBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) else {
                    print("Failed to generate mask")
                    DispatchQueue.main.async { isProcessingBackgroundRemoval = false }
                    return
                }

                let maskImage = CIImage(cvPixelBuffer: maskBuffer)
                let transparentBackground = CIImage(color: .clear).cropped(to: ciInput.extent)

                // Create border by expanding mask slightly
                let borderMask: CIImage
                if borderWidth > 0 {
                    let morphology = CIFilter.morphologyMaximum()
                    morphology.inputImage = maskImage
                    morphology.radius = borderWidth
                    borderMask = morphology.outputImage ?? maskImage
                } else {
                    borderMask = maskImage
                }

                // Fill the border mask with black
                let blackBorder = CIImage(color: .black)
                    .cropped(to: ciInput.extent)
                    .applyingFilter("CIBlendWithMask", parameters: [
                        "inputBackgroundImage": CIImage(color: .clear).cropped(to: ciInput.extent),
                        "inputMaskImage": borderMask
                    ])

                // Blend original image over black border
                let blendFilter = CIFilter.blendWithMask()
                blendFilter.inputImage = ciInput
                blendFilter.backgroundImage = blackBorder
                blendFilter.maskImage = maskImage

                if let output = blendFilter.outputImage,
                   let cgImage = CIContext().createCGImage(output, from: output.extent) {
                    let finalUIImage = UIImage(cgImage: cgImage, scale: currentImage.scale, orientation: currentImage.imageOrientation)

                    DispatchQueue.main.async {
                        self.currentImage = finalUIImage
                        self.isProcessingBackgroundRemoval = false
                        self.hasBackgroundRemoved = true
                        self.clearEraseSession()
                        self.recordEditHistory()
                    }
                } else {
                    DispatchQueue.main.async {
                        print("Failed to create output image")
                        self.isProcessingBackgroundRemoval = false
                    }
                }

            } catch {
                DispatchQueue.main.async {
                    print("Error during background removal: \(error)")
                    self.isProcessingBackgroundRemoval = false
                }
            }
        }
    }

    func cropAndSaveImage() {
    let canvasSize = cropViewSize
    let imageSize = currentImage.size

    // 1. Base scale to cover the square view (mimics .aspectRatio(.fill), centered)
    let baseScale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)

    // 2. User gesture scale applied on top of base fill
    let finalScale = baseScale * scale

    // 3. Calculate how big the image will be when drawn
    let drawnSize = CGSize(width: imageSize.width * finalScale,
                           height: imageSize.height * finalScale)

    // 4. Calculate centered origin, then apply user drag offset
    let origin = CGPoint(
        x: (canvasSize.width - drawnSize.width) / 2 + offset.width,
        y: (canvasSize.height - drawnSize.height) / 2 + offset.height
    )

    // 5. Render the image exactly how it appears onscreen
    let rendererFormat = UIGraphicsImageRendererFormat()
    rendererFormat.opaque = false

    let renderer = UIGraphicsImageRenderer(size: canvasSize, format: rendererFormat)
    let croppedImage = renderer.image { ctx in
        UIColor.clear.setFill()
        ctx.fill(CGRect(origin: .zero, size: canvasSize))
        currentImage.draw(in: CGRect(origin: origin, size: drawnSize))
    }

    onCrop(croppedImage)
    dismiss()
}


}
