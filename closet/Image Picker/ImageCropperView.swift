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

    // The image currently shown/edited
    @State private var currentImage: UIImage
    // Store the original for undo
    @State private var originalForUndo: UIImage
    // Transform state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    @State private var cropViewSize: CGSize = .zero

    @State private var isProcessingBackgroundRemoval = false

    @Environment(\.dismiss) private var dismiss

    init(originalImage: UIImage, onCrop: @escaping (UIImage) -> Void) {
        self.originalImage = originalImage
        self.onCrop = onCrop
        // Initialize the current image and undo image to original
        _currentImage = State(initialValue: originalImage)
        _originalForUndo = State(initialValue: originalImage)
    }

    var body: some View {
        VStack {
            ZStack {
                Color.black.opacity(0.1)

                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)

                    Image(uiImage: currentImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            DragGesture().onChanged { self.offset = $0.translation }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { value in
                                    lastScale = scale
                                }
                        )
                        .frame(width: side, height: side)
                        .clipped()
                        .onAppear {
                            cropViewSize = CGSize(width: side, height: side)
                        }
                        .onChange(of: geo.size) { newSize in
                            let s = min(newSize.width, newSize.height)
                            cropViewSize = CGSize(width: s, height: s)
                        }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .border(Color.black.opacity(0.2))

            }

           /* if isProcessingBackgroundRemoval {
                ProgressView("Removing Background...")
                    .padding()
            }*/

            
        }
        .navigationTitle("Crop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .foregroundColor(Color.red)
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
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
                    .disabled(isProcessingBackgroundRemoval)
                }
                .padding()
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    cropAndSaveImage()
                }
            }
        }
    }
    
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
/* Old removebackground without border
    func removeBackground() {
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
                    DispatchQueue.main.async {
                        isProcessingBackgroundRemoval = false
                    }
                    return
                }

                guard let maskBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) else {
                    print("Failed to generate mask")
                    DispatchQueue.main.async {
                        isProcessingBackgroundRemoval = false
                    }
                    return
                }

                let maskImage = CIImage(cvPixelBuffer: maskBuffer)
                let transparentBackground = CIImage(color: .clear).cropped(to: ciInput.extent)

                let blendFilter = CIFilter.blendWithMask()
                blendFilter.inputImage = ciInput
                blendFilter.backgroundImage = transparentBackground
                blendFilter.maskImage = maskImage

                if let output = blendFilter.outputImage,
                   let cgImage = CIContext().createCGImage(output, from: output.extent) {
                    let finalUIImage = UIImage(cgImage: cgImage, scale: currentImage.scale, orientation: currentImage.imageOrientation)

                    DispatchQueue.main.async {
                        self.originalForUndo = self.currentImage // save current for undo
                        self.currentImage = finalUIImage
                        self.isProcessingBackgroundRemoval = false
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
*/
    func undoBackgroundRemoval() {
        currentImage = originalForUndo
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
     //   rendererFormat.scale = 1
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
