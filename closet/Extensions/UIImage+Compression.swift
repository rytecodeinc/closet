//
//  UIImage+Compression.swift
//  closet
//
//  Created by Dan Warner on 1/7/26.
//

import UIKit

extension UIImage {

    /// Returns true when the image contains at least one non-opaque pixel.
    /// Items with removed backgrounds are transparent; regular photos are fully opaque.
    var hasTransparency: Bool {
        guard let cgImage = self.cgImage else { return false }
        let alphaInfo = cgImage.alphaInfo
        return alphaInfo == .first
            || alphaInfo == .last
            || alphaInfo == .premultipliedFirst
            || alphaInfo == .premultipliedLast
            || alphaInfo == .alphaOnly
    }

    /// Compresses an opaque image to a target file size (default ~200 KB).
    /// Transparent images are NOT passed through this path — use processForStorage() instead.
    func compressForStorage(maxFileSizeKB: Int = 200) -> Data? {
        var compression: CGFloat = 0.8
        var imageData = self.jpegData(compressionQuality: compression)
        
        while let data = imageData,
              data.count > maxFileSizeKB * 1024,
              compression > 0.1 {
            compression -= 0.1
            imageData = self.jpegData(compressionQuality: compression)
        }
        
        return imageData
    }
    
    /// Resizes image to maximum dimension while maintaining aspect ratio.
    /// Always renders with opaque=false so alpha is preserved if present.
    func resizeForStorage(maxDimension: CGFloat = 1200) -> UIImage? {
        let currentMaxDimension = max(size.width, size.height)
        
        guard currentMaxDimension > maxDimension else {
            return self
        }
        
        let scale = maxDimension / currentMaxDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false   // preserve alpha channel
        format.scale = 1.0
        format.preferredRange = .extended
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resizedImage = renderer.image { context in
            context.cgContext.interpolationQuality = .high
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage
    }
    
    /// Generates a thumbnail for grid views (default 300 px).
    /// Uses PNG when the source is transparent so background-removed items
    /// render correctly anywhere a thumbnail is displayed.
    func generateThumbnail(size: CGFloat = 300) -> Data? {
        guard let resized = self.resizeForStorage(maxDimension: size) else { return nil }
        if resized.hasTransparency {
            return resized.pngData()
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
    
    /// Optimized processing: resize first, then encode.
    /// Transparent images are encoded as PNG to preserve alpha;
    /// opaque images are encoded as JPEG for smaller file size.
    func processForStorage(maxDimension: CGFloat = 1200, maxFileSizeKB: Int = 200) -> Data? {
        guard let resized = self.resizeForStorage(maxDimension: maxDimension) else {
            return nil
        }
        if resized.hasTransparency {
            return resized.pngData()
        }
        return resized.compressForStorage(maxFileSizeKB: maxFileSizeKB)
    }

    /// Square viewport with SwiftUI-style **aspect ratio fill** (centered crop), matching `ItemDetailView`’s hero image framing.
    /// This is the same geometric model as `Image(uiImage:).resizable().aspectRatio(contentMode: .fill)` in a square frame.
    func squareAspectFillCenterCropped(side: CGFloat) -> UIImage {
        let s = max(side, 1)
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let scale = max(s / w, s / h)
        let drawnW = w * scale
        let drawnH = h * scale
        let originX = (s - drawnW) / 2
        let originY = (s - drawnH) / 2

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1.0
        format.preferredRange = .extended

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: format)
        return renderer.image { _ in
            UIColor.clear.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: CGSize(width: s, height: s))).fill()
            self.draw(in: CGRect(x: originX, y: originY, width: drawnW, height: drawnH))
        }
    }

    /// Pixel-space bounds of non-transparent pixels. Full image when there is no alpha channel.
    func nonTransparentContentBoundsInPixelSpace(alphaThreshold: UInt8 = 12) -> CGRect? {
        guard let cgImage = cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return CGRect(x: 0, y: 0, width: width, height: height)
        default:
            break
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        let bytesPerRow = width * 4
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        let threshold = Int(alphaThreshold)

        for y in 0..<height {
            let row = data.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let alpha = Int(row.load(fromByteOffset: x * 4 + 3, as: UInt8.self))
                if alpha > threshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX <= maxX, minY <= maxY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Crops using precomputed normalized bounds (no alpha scan).
    func cropped(toNormalizedBounds bounds: NormalizedContentBounds) -> UIImage? {
        guard let cgImage = cgImage else { return nil }
        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)
        let rect = CGRect(
            x: bounds.x * pixelW,
            y: bounds.y * pixelH,
            width: bounds.width * pixelW,
            height: bounds.height * pixelH
        ).integral
        guard rect.width > 1, rect.height > 1, let cropped = cgImage.cropping(to: rect) else {
            return nil
        }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }

    /// Crops to opaque content bounds in pixel space, with optional outward padding (clamped to image).
    func croppedToOpaqueContentBounds(paddingRatio: CGFloat = 0.04) -> UIImage? {
        guard let cgImage = cgImage else { return nil }
        guard var rect = nonTransparentContentBoundsInPixelSpace() else { return self }

        let padX = rect.width * paddingRatio
        let padY = rect.height * paddingRatio
        rect = rect.insetBy(dx: -padX, dy: -padY)
        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        rect = rect.intersection(imageRect)
        guard rect.width > 1, rect.height > 1, let cropped = cgImage.cropping(to: rect.integral) else {
            return nil
        }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }

    /// After background removal: crop to subject bounds, then **aspect-fit** the subject in a square (centered, letterboxed).
    /// Use this for bulk import so the full garment stays visible when the hero uses `.fill`.
    func squareAspectFitSubjectInSquare(side: CGFloat, contentPaddingRatio: CGFloat = 0.04) -> UIImage {
        let s = max(side, 1)
        let subject = croppedToOpaqueContentBounds(paddingRatio: contentPaddingRatio) ?? self

        let w = max(subject.size.width, 1)
        let h = max(subject.size.height, 1)
        let fitScale = min(s / w, s / h)
        let drawnW = w * fitScale
        let drawnH = h * fitScale
        let originX = (s - drawnW) / 2
        let originY = (s - drawnH) / 2

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1.0
        format.preferredRange = .extended

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: format)
        return renderer.image { context in
            UIColor.clear.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: CGSize(width: s, height: s))).fill()
            context.cgContext.interpolationQuality = .high
            subject.draw(in: CGRect(x: originX, y: originY, width: drawnW, height: drawnH))
        }
    }

    /// Thumbnail bytes for grid/hero when the master is already square with subject aspect-fit (e.g. bulk import).
    func gridThumbnailDataFromSquareMaster(outputSide: CGFloat = 300) -> Data? {
        guard let resized = resizeForStorage(maxDimension: outputSide) else { return nil }
        if resized.hasTransparency {
            return resized.pngData()
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    /// Thumbnail bytes for `ItemView` grids — aspect-fits subject in square (matches bulk import / hero for cutouts).
    func gridThumbnailDataMatchingItemDetailHero(outputSide: CGFloat = 300) -> Data? {
        let fitted = squareAspectFitSubjectInSquare(side: outputSide)
        if fitted.hasTransparency {
            return fitted.pngData()
        }
        return fitted.jpegData(compressionQuality: 0.7)
    }

    /// Encodes for R2 / worker upload: targets **under `maxBytes`** (default 4.8 MB under a 5 MB limit).
    /// Opaque → JPEG with quality + dimension reduction; alpha → PNG with progressive downscale.
    func encodeForR2Upload(maxBytes: Int = 4_800_000) -> Data? {
        if hasTransparency {
            var working: UIImage = self
            for _ in 0..<20 {
                if let png = working.pngData(), png.count <= maxBytes {
                    return png
                }
                let maxDim = max(working.size.width, working.size.height) * 0.86
                guard maxDim >= 220, let next = working.resizeForStorage(maxDimension: maxDim) else { break }
                working = next
            }
            return working.pngData()
        }

        var maxDim = min(2048, max(size.width, size.height))
        guard var working = resizeForStorage(maxDimension: maxDim) else {
            return jpegData(compressionQuality: 0.45)
        }

        for _ in 0..<24 {
            var q: CGFloat = 0.88
            while q >= 0.18 {
                if let data = working.jpegData(compressionQuality: q), data.count <= maxBytes {
                    return data
                }
                q -= 0.06
            }
            maxDim *= 0.86
            guard maxDim >= 360, let next = working.resizeForStorage(maxDimension: maxDim) else { break }
            working = next
        }
        return working.jpegData(compressionQuality: 0.35)
    }

    /// Square center-crop, then composite on white so the result is opaque JPEG-friendly (matches R2 worker `Content-Type: image/jpeg` for `avatar.jpg`).
    func profileAvatarImageForUpload(side: CGFloat = 1024) -> UIImage {
        let cropped = squareAspectFillCenterCropped(side: side)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = cropped.scale
        let renderer = UIGraphicsImageRenderer(size: cropped.size, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: cropped.size)).fill()
            cropped.draw(at: .zero)
        }
    }
}

