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
    /// When false, rely on navigation back instead of a leading Cancel button.
    let showsCancelButton: Bool

    // The image currently shown/edited
    @State private var currentImage: UIImage
    /// Linear history for undo/redo (background removal, erase, repaint).
    @State private var editHistory: [EditSnapshot]
    @State private var editHistoryIndex: Int
    // Transform state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero
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
    private static let editActionsRowHeight: CGFloat = 56
    private static let brushActionsRowHeight: CGFloat = 56
    private static let brushSliderRowHeight: CGFloat = 52
    private static let framingActionsRowHeight: CGFloat = 56

    private var stackedActionBarHeight: CGFloat {
        var height = Self.framingActionsRowHeight + 1
        height += Self.editActionsRowHeight + 1 + Self.brushActionsRowHeight
        if isBrushEditing {
            height += 1 + Self.brushSliderRowHeight
        }
        return height
    }

    private func cropSquareSide(for geoSize: CGSize) -> CGFloat {
        min(geoSize.width, max(0, geoSize.height - stackedActionBarHeight))
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
        onCancel: (() -> Void)? = nil,
        showsCancelButton: Bool = true
    ) {
        self.originalImage = originalImage
        self.onCrop = onCrop
        self.isEditing = isEditing
        self.onCancel = onCancel
        self.showsCancelButton = showsCancelButton
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
                Color(.systemBackground)

                GeometryReader { geo in
                    let side = cropSquareSide(for: geo.size)

                    VStack(spacing: 0) {
                        HStack {
                            Spacer(minLength: 0)

                            ZStack {
                                cropTransparencyCheckerboard(side: side)
                                cropImageLayer(side: side)
                            }
                            .frame(width: side, height: side)
                            .contentShape(Rectangle())
                            .highPriorityGesture(brushDragGesture(side: side), including: isBrushEditing ? .all : .subviews)
                            .onAppear {
                                cropViewSize = CGSize(width: side, height: side)
                            }
                            .onChange(of: geo.size) { _, newSize in
                                let s = cropSquareSide(for: newSize)
                                cropViewSize = CGSize(width: s, height: s)
                            }
                            .onChange(of: isBrushEditing) { _, _ in
                                let s = cropSquareSide(for: geo.size)
                                cropViewSize = CGSize(width: s, height: s)
                            }

                            Spacer(minLength: 0)
                        }
                        Divider()
                        VStack(spacing: 0) {
                            cropFramingActionsRow
                            Divider()
                            autoRemoveBackgroundRow
                            Divider()
                            cropBrushActionsRow
                            if isBrushEditing {
                                Divider()
                                brushSizeSliderBar
                            }
                        }
                        .frame(width: side)
                        .animation(.easeInOut(duration: 0.2), value: isBrushEditing)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            if showsCancelButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel {
                            onCancel()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") {
                    cropAndSaveImage()
                }
            }
        }
    }

    /// Size control for erase and repaint — shown in the row below erase/repaint when active.
    private var brushSizeSliderBar: some View {
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
        .frame(maxWidth: .infinity)
        .frame(height: Self.brushSliderRowHeight)
        .background(Color(.systemBackground))
    }

    private var isRemoveBackgroundEnabled: Bool {
        !isProcessingBackgroundRemoval && !hasBackgroundRemoved
    }

    private var canRestoreToOriginal: Bool {
        guard !isProcessingBackgroundRemoval else { return false }
        guard let initial = editHistory.first else { return false }
        let hasTransformChanges = scale != 1.0 || rotation != .zero || offset != .zero
        return hasEraseEdits
            || hasBackgroundRemoved
            || hasTransformChanges
            || currentImage !== initial.currentImage
            || eraseSourceImage != nil
            || !brushEditOps.isEmpty
    }

    @ViewBuilder
    private func cropDisplayedImage(side: CGFloat) -> some View {
        Image(uiImage: currentImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .scaleEffect(scale)
            .rotationEffect(rotation)
            .offset(offset)
            .frame(width: side, height: side)
            .clipped()
    }

    private var cropTransformGestures: some Gesture {
        SimultaneousGesture(
            SimultaneousGesture(
                DragGesture(minimumDistance: 2)
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
                    },
                MagnificationGesture()
                    .onChanged { value in
                        scale = lastScale * value
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            ),
            RotationGesture()
                .onChanged { value in
                    rotation = lastRotation + value
                }
                .onEnded { _ in
                    lastRotation = rotation
                }
        )
    }

    /// Remove Background — centered on its row.
    private var autoRemoveBackgroundRow: some View {
        HStack {
            Spacer(minLength: 0)
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
                .foregroundStyle(isRemoveBackgroundEnabled ? Color.white : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isRemoveBackgroundEnabled ? Color.accentColor : Color(.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.vertical)
            .disabled(!isRemoveBackgroundEnabled)
            .accessibilityLabel("Remove Background")
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
    }

    /// Erase / Repaint (leading), Restore (center), Undo / Redo (trailing).
    private var cropBrushActionsRow: some View {
        ZStack {
            HStack(spacing: 0) {
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

                Spacer(minLength: 0)

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
                }
            }

            Button {
                restoreToOriginal()
            } label: {
                cropToolLabel(
                    icon: "arrow.counterclockwise",
                    title: "Restore",
                    tint: canRestoreToOriginal ? .red : .secondary
                )
            }
            .disabled(!canRestoreToOriginal)
            .accessibilityLabel("Restore original image")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: Self.brushActionsRowHeight)
        .background(Color(.systemBackground))
    }

    /// Fit / Fill / Center / Rotate controls directly under the crop square.
    private var cropFramingActionsRow: some View {
        HStack(spacing: 0) {
            framingToolButton(icon: "arrow.down.right.and.arrow.up.left", title: "Fit") {
                applyFitFraming()
            }
            .accessibilityLabel("Fit image in crop area")

            framingToolButton(icon: "arrow.up.left.and.arrow.down.right", title: "Fill") {
                applyFillFraming()
            }
            .accessibilityLabel("Fill crop area with image")

            framingToolButton(icon: "scope", title: "Center") {
                applyCenterFraming()
            }
            .accessibilityLabel("Center image in crop area")

            framingToolButton(icon: "arrow.left.and.right", title: "H Center") {
                applyHorizontalCenterFraming()
            }
            .accessibilityLabel("Center image horizontally")

            framingToolButton(icon: "arrow.up.and.down", title: "V Center") {
                applyVerticalCenterFraming()
            }
            .accessibilityLabel("Center image vertically")

            framingToolButton(icon: "rotate.right", title: "Rotate") {
                applyRotate90Degrees()
            }
            .accessibilityLabel("Rotate image 90 degrees")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.framingActionsRowHeight)
        .background(Color(.systemBackground))
    }

    private func framingToolButton(
        icon: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            cropToolLabel(icon: icon, title: title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isProcessingBackgroundRemoval || isBrushEditing)
    }

    private func applyFillFraming() {
        applyContentFraming(mode: .fill)
    }

    private func applyFitFraming() {
        applyContentFraming(mode: .fit)
    }

    private func applyCenterFraming() {
        applyContentFraming(mode: .center)
    }

    private func applyHorizontalCenterFraming() {
        applyAxisCentering(.horizontal)
    }

    private func applyVerticalCenterFraming() {
        applyAxisCentering(.vertical)
    }

    private enum AxisCentering {
        case horizontal
        case vertical
    }

    /// Centers content on one axis while preserving scale and the other axis offset.
    private func applyAxisCentering(_ axis: AxisCentering) {
        guard cropViewSize.width > 0, cropViewSize.height > 0 else { return }

        let imageSize = currentImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let contentRect = contentRectInImagePoints(for: currentImage)
        guard contentRect.width > 0, contentRect.height > 0 else { return }

        let baseScale = baseFillScale(canvas: cropViewSize, imageSize: imageSize)
        guard baseScale > 0 else { return }

        let effectiveScale = baseScale * scale
        let centeredOffset = centerOffsetForContent(
            effectiveScale: effectiveScale,
            canvas: cropViewSize,
            imageSize: imageSize,
            contentRect: contentRect
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            switch axis {
            case .horizontal:
                offset.width = centeredOffset.width
            case .vertical:
                offset.height = centeredOffset.height
            }
            lastOffset = offset
        }
    }

    private func applyRotate90Degrees() {
        guard !isProcessingBackgroundRemoval, !isBrushEditing else { return }

        currentImage = rotateUIImage90DegreesClockwise(normalizedImage(currentImage))
        clearEraseSession()

        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1.0
            lastScale = 1.0
            rotation = .zero
            lastRotation = .zero
            offset = .zero
            lastOffset = .zero
        }
        recordEditHistory()
    }

    /// Bakes orientation, then rotates pixel data 90° clockwise.
    private func rotateUIImage90DegreesClockwise(_ image: UIImage) -> UIImage {
        let size = image.size
        let newSize = CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: .pi / 2)
            cg.translateBy(x: -size.width / 2, y: -size.height / 2)
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private enum ContentFramingMode {
        case fill
        case fit
        case center
    }

    /// Visible (non-transparent) region of `image` in UIKit point coordinates.
    private func contentRectInImagePoints(for image: UIImage) -> CGRect {
        let normalized = PhotoContentBounds.normalizedBounds(for: image)
        let size = image.size
        return CGRect(
            x: normalized.x * size.width,
            y: normalized.y * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }

    private func baseFillScale(canvas: CGSize, imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(canvas.width / imageSize.width, canvas.height / imageSize.height)
    }

    /// Offset that places the content rect's center on the crop canvas center at `effectiveScale`.
    private func centerOffsetForContent(
        effectiveScale: CGFloat,
        canvas: CGSize,
        imageSize: CGSize,
        contentRect: CGRect
    ) -> CGSize {
        CGSize(
            width: effectiveScale * (imageSize.width / 2 - contentRect.midX),
            height: effectiveScale * (imageSize.height / 2 - contentRect.midY)
        )
    }

    private func applyContentFraming(mode: ContentFramingMode) {
        guard cropViewSize.width > 0, cropViewSize.height > 0 else { return }

        let imageSize = currentImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let contentRect = contentRectInImagePoints(for: currentImage)
        guard contentRect.width > 0, contentRect.height > 0 else { return }

        let baseScale = baseFillScale(canvas: cropViewSize, imageSize: imageSize)
        guard baseScale > 0 else { return }

        let effectiveScale: CGFloat
        let newScale: CGFloat

        switch mode {
        case .fill:
            effectiveScale = max(
                cropViewSize.width / contentRect.width,
                cropViewSize.height / contentRect.height
            )
            newScale = effectiveScale / baseScale
        case .fit:
            effectiveScale = min(
                cropViewSize.width / contentRect.width,
                cropViewSize.height / contentRect.height
            )
            newScale = effectiveScale / baseScale
        case .center:
            effectiveScale = baseScale * scale
            newScale = scale
        }

        let newOffset = centerOffsetForContent(
            effectiveScale: effectiveScale,
            canvas: cropViewSize,
            imageSize: imageSize,
            contentRect: contentRect
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            scale = newScale
            lastScale = newScale
            rotation = .zero
            lastRotation = .zero
            offset = newOffset
            lastOffset = newOffset
        }
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
        let sizeChanged = currentImage.size != snapshot.currentImage.size
        currentImage = snapshot.currentImage
        eraseSourceImage = snapshot.eraseSourceImage
        brushEditOps = snapshot.brushEditOps
        hasBackgroundRemoved = snapshot.hasBackgroundRemoved
        activeEraseStroke = nil
        activeRestoreStroke = nil
        lastErasePoint = nil
        hasEraseEdits = !brushEditOps.isEmpty
        if sizeChanged {
            scale = 1.0
            lastScale = 1.0
            rotation = .zero
            lastRotation = .zero
            offset = .zero
            lastOffset = .zero
        }
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
        if isBrushEditing {
            cropDisplayedImage(side: side)
        } else {
            cropDisplayedImage(side: side)
                .gesture(cropTransformGestures)
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

    /// Resets image and edit flags to the original imported photo (undoes background removal, rotation, erase, etc.).
    func restoreToOriginal() {
        guard canRestoreToOriginal, let initial = editHistory.first else { return }

        commitActiveEraseStroke()
        commitActiveRestoreStroke()
        isErasing = false
        isRestoringBrush = false

        currentImage = initial.currentImage
        clearEraseSession()
        hasBackgroundRemoved = false

        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1.0
            lastScale = 1.0
            rotation = .zero
            lastRotation = .zero
            offset = .zero
            lastOffset = .zero
        }
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

        var point = CGPoint(
            x: touchPoint.x - side / 2 - offset.width,
            y: touchPoint.y - side / 2 - offset.height
        )

        let radians = -CGFloat(rotation.radians)
        let cosR = cos(radians)
        let sinR = sin(radians)
        let rotatedX = point.x * cosR - point.y * sinR
        let rotatedY = point.x * sinR + point.y * cosR
        point = CGPoint(x: rotatedX, y: rotatedY)

        guard effectiveScale > 0 else {
            return CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        }

        let x = point.x / effectiveScale + imageSize.width / 2
        let y = point.y / effectiveScale + imageSize.height / 2
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
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

        let side = canvasSize.width
        let captureView = ZStack {
            Color.clear
            cropDisplayedImage(side: side)
        }
        .frame(width: side, height: side)

        let renderer = ImageRenderer(content: captureView)
        renderer.isOpaque = false
        renderer.scale = UIScreen.main.scale

        guard let croppedImage = renderer.uiImage else { return }
        onCrop(croppedImage)
        dismiss()
    }


}
