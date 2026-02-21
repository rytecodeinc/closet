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

    // The image currently shown/edited
    @State private var currentImage: UIImage
    // Store the original for undo
    @State private var originalForUndo: UIImage
    // Transform state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero // Track the offset at the start of drag
    @State private var isDragging: Bool = false // Track if we're currently dragging

    @State private var cropViewSize: CGSize = .zero

    @State private var isProcessingBackgroundRemoval = false
    @State private var hasBackgroundRemoved = false

    // Erase mode state
    @State private var isErasing: Bool = false
    @State private var eraseMask: UIImage?
    @State private var eraserBrushSize: CGFloat = 30.0
    @State private var lastErasePoint: CGPoint?
    
    struct ErasePath {
        var path: Path
        var lineWidth: CGFloat
    }
    
    @State private var erasePaths: [ErasePath] = []
    @State private var currentErasePath = Path()

    @Environment(\.dismiss) private var dismiss
    
    init(originalImage: UIImage, onCrop: @escaping (UIImage) -> Void, isEditing: Bool = false) {
        self.originalImage = originalImage
        self.onCrop = onCrop
        self.isEditing = isEditing
        // Initialize the current image and undo image to original
        _currentImage = State(initialValue: originalImage)
        _originalForUndo = State(initialValue: originalImage)
    }

    var body: some View {
        VStack {
            ZStack {
                Color.black

                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            
                            ZStack {
                                Color.white
                                    .frame(width: side, height: side)
                                // BACKING IMAGE LAYER with gestures
                                Image(uiImage: currentImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(scale)
                                    .offset(offset)
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                guard !isErasing else { return }
                                                // On first change of a new drag, capture current offset as starting point
                                                if !isDragging {
                                                    lastOffset = offset
                                                    isDragging = true
                                                }
                                                // Add translation to the last offset for smooth movement
                                                self.offset = CGSize(
                                                    width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height
                                                )
                                            }
                                            .onEnded { _ in
                                                guard !isErasing else { return }
                                                // Update lastOffset when drag ends for next drag
                                                lastOffset = offset
                                                isDragging = false
                                            }
                                    )
                                    .simultaneousGesture(
                                        MagnificationGesture()
                                            .onChanged { value in
                                                guard !isErasing else { return }
                                                scale = lastScale * value
                                            }
                                            .onEnded { value in
                                                guard !isErasing else { return }
                                                lastScale = scale
                                            }
                                    )
                                    .frame(width: side, height: side)
                                    .clipped()

                                // DRAWING (MASK) LAYER for eraser
                                Canvas { context, _ in
                                    for erase in erasePaths {
                                        context.stroke(
                                            erase.path,
                                            with: .color(.white),
                                            lineWidth: erase.lineWidth
                                        )
                                    }

                                    context.stroke(
                                        currentErasePath,
                                        with: .color(.white),
                                        lineWidth: eraserBrushSize
                                    )
                                }
                                .frame(width: side, height: side)
                                .allowsHitTesting(isErasing)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard isErasing else { return }

                                            if currentErasePath.isEmpty {
                                                currentErasePath.move(to: value.location)
                                            } else {
                                                currentErasePath.addLine(to: value.location)
                                            }
                                            
                                            handleEraseDrag(at: value.location, side: side)
                                        }
                                        .onEnded { _ in
                                            guard isErasing else { return }

                                            erasePaths.append(
                                                ErasePath(
                                                    path: currentErasePath,
                                                    lineWidth: eraserBrushSize
                                                )
                                            )
                                            currentErasePath = Path()
                                            lastErasePoint = nil
                                        }
                                )
                            }
                            .frame(width: side, height: side)
                            .onAppear {
                                cropViewSize = CGSize(width: side, height: side)
                            }
                            .onChange(of: geo.size) { newSize in
                                let s = min(newSize.width, newSize.height)
                                cropViewSize = CGSize(width: s, height: s)
                            }
                            
                            Spacer()
                        }
                        Spacer()
                    }
                }
}
           /* if isProcessingBackgroundRemoval {
                ProgressView("Removing Background...")
                    .padding()
            }*/

            
        }
        .navigationTitle("Crop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button {
                        toggleEraseMode()
                    } label: {
                        VStack {
                            Image(systemName: "eraser")
                            Text("Erase")
                        }
                        .foregroundColor(isErasing ? .blue : .primary)
                    }
                    .disabled(isProcessingBackgroundRemoval)
                    
                    Button {
                        restoreErase()
                    } label: {
                        VStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Restore")
                        }
                    }
                    .disabled(isProcessingBackgroundRemoval)
                    
                    Button {
            undoBackgroundRemoval()
        } label: {
            VStack{
                Image(systemName: "arrowshape.turn.up.backward")
                Text("Undo")
            }
        }
        .disabled(isProcessingBackgroundRemoval || currentImage == originalForUndo)
        
        Button("Remove Background") {
            removeBackground()
        }
        .buttonStyle(.borderedProminent)
        .disabled(isProcessingBackgroundRemoval || hasBackgroundRemoved)
    }
    .padding()
}

            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") {
                    cropAndSaveImage()
                }
            }
        }
    }
// MARK: - Erase Functions
    
    func toggleEraseMode() {
        isErasing.toggle()
        if isErasing && eraseMask == nil {
            initializeEraseMask()
        }
    }
    
    func initializeEraseMask() {
        let imageSize = originalImage.size
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        
        eraseMask = renderer.image { ctx in
            // Fill with white (fully opaque) - white in mask means show the image
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: imageSize))
        }
    }
    
    func restoreErase() {
        // Reset mask to fully opaque (all white) to restore the entire image
        initializeEraseMask()
        
        // Clear all erase paths
        erasePaths.removeAll()
        currentErasePath = Path()
        lastErasePoint = nil
        
        // Reapply the mask to update the displayed image (showing full original image)
        applyEraseMask()
        
        // Reset background removal state to allow removing background again
        hasBackgroundRemoved = false
    }
    
    func handleEraseDrag(at location: CGPoint, side: CGFloat) {
        // Ensure mask is initialized
        if eraseMask == nil {
            initializeEraseMask()
        }
        
        guard eraseMask != nil else { return }
        
        drawEraseAtPoint(location: location, side: side)
    }
    
    func drawEraseAtPoint(location: CGPoint, side: CGFloat) {
        guard let mask = eraseMask else { return }
        // Convert touch location to image coordinates
        let imagePoint = convertToImageCoordinates(
            touchPoint: location,
            side: side
        )
        
        let imageSize = originalImage.size
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        
        let newMask = renderer.image { ctx in
            // Draw the existing mask
            mask.draw(in: CGRect(origin: .zero, size: imageSize))
            
            let cgContext = ctx.cgContext
            
            // Draw black (which represents transparency in the mask)
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.setStrokeColor(UIColor.white.cgColor)
            
            // Draw circle at current point
            let brushRect = CGRect(
                x: imagePoint.x - eraserBrushSize / 2,
                y: imagePoint.y - eraserBrushSize / 2,
                width: eraserBrushSize,
                height: eraserBrushSize
            )
            cgContext.fillEllipse(in: brushRect)
            
            // Draw line to previous point for smooth continuous strokes
            if let lastPoint = lastErasePoint {
                cgContext.setLineWidth(eraserBrushSize)
                cgContext.setLineCap(.round)
                cgContext.setLineJoin(.round)
                cgContext.move(to: lastPoint)
                cgContext.addLine(to: imagePoint)
                cgContext.strokePath()
            }
        }
        
        eraseMask = newMask
        lastErasePoint = imagePoint
        
        // Apply the mask to update the displayed image in real-time
        applyEraseMask()
    }
    
    func convertToImageCoordinates(touchPoint: CGPoint, side: CGFloat) -> CGPoint {
        let imageSize = originalImage.size

        // Aspect-fit scale
        let fitScale = min(side / imageSize.width, side / imageSize.height)

        let fittedSize = CGSize(
            width: imageSize.width * fitScale,
            height: imageSize.height * fitScale
        )

        // Image is centered *by SwiftUI*, so compute letterbox offset
        let xInset = (side - fittedSize.width) / 2
        let yInset = (side - fittedSize.height) / 2

        // Convert touch → image-local
        let x = (touchPoint.x - xInset) / fitScale
        let y = (touchPoint.y - yInset) / fitScale

        return CGPoint(
            x: max(0, min(imageSize.width, x)),
            y: max(0, min(imageSize.height, y))
        )
    }


    
    func applyEraseMask() {
        guard let mask = eraseMask,
              let originalCI = CIImage(image: originalImage),
              let maskCI = CIImage(image: mask) else {
            return
        }
        
        // Create a transparent background
        let transparentBackground = CIImage(color: .clear).cropped(to: originalCI.extent)
        
        // Apply the mask using blendWithMask filter
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = originalCI
        blendFilter.backgroundImage = transparentBackground
        blendFilter.maskImage = maskCI
        
        guard let output = blendFilter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else {
            return
        }
        
        let maskedImage = UIImage(
            cgImage: cgImage,
            scale: originalImage.scale,
            orientation: originalImage.imageOrientation
        )
        
        currentImage = maskedImage
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
                        self.originalForUndo = self.currentImage // save for undo
                        self.currentImage = finalUIImage
                        self.isProcessingBackgroundRemoval = false
                        self.hasBackgroundRemoved = true
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

    func undoBackgroundRemoval() {
        currentImage = originalForUndo
        hasBackgroundRemoved = false
    }

    func cropAndSaveImage() {
    let canvasSize = cropViewSize
    let imageSize = currentImage.size

    // 1. Base scale used to fit image inside the square view (mimics .aspectRatio(.fit))
    let baseScale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)

    // 2. User gesture scale applied on top of base fit
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
        
        // Apply erase paths
        ctx.cgContext.setBlendMode(.clear)
        ctx.cgContext.setLineCap(.round)
        ctx.cgContext.setLineJoin(.round)

        for erase in erasePaths {
            ctx.cgContext.setLineWidth(erase.lineWidth)
            ctx.cgContext.addPath(erase.path.cgPath)
            ctx.cgContext.strokePath()
        }
    }

    onCrop(croppedImage)
    dismiss()
}


}
