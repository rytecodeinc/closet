//
//  BackgroundRemovalService.swift
//  closet
//
//  Shared Vision foreground mask pipeline (same approach as `ImageCropperView.removeBackground`).
//

import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum BackgroundRemovalService {

    /// Removes background using Vision; returns original image if Vision fails.
    static func removeBackground(from image: UIImage, borderWidth: Float = 1.0) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            guard let ciInput = CIImage(image: image) else { return image }

            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: ciInput)

            do {
                try handler.perform([request])
                guard let result = request.results?.first else { return image }
                guard let maskBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) else {
                    return image
                }

                let maskImage = CIImage(cvPixelBuffer: maskBuffer)
                let transparentBackground = CIImage(color: .clear).cropped(to: ciInput.extent)

                let borderMask: CIImage
                if borderWidth > 0 {
                    let morphology = CIFilter.morphologyMaximum()
                    morphology.inputImage = maskImage
                    morphology.radius = borderWidth
                    borderMask = morphology.outputImage ?? maskImage
                } else {
                    borderMask = maskImage
                }

                let blackBorder = CIImage(color: .black)
                    .cropped(to: ciInput.extent)
                    .applyingFilter("CIBlendWithMask", parameters: [
                        "inputBackgroundImage": CIImage(color: .clear).cropped(to: ciInput.extent),
                        "inputMaskImage": borderMask
                    ])

                let blendFilter = CIFilter.blendWithMask()
                blendFilter.inputImage = ciInput
                blendFilter.backgroundImage = blackBorder
                blendFilter.maskImage = maskImage

                guard let output = blendFilter.outputImage,
                      let cgImage = CIContext().createCGImage(output, from: output.extent) else {
                    return image
                }

                return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
            } catch {
                return image
            }
        }.value
    }
}
