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
}

