//
//  UIImage+Compression.swift
//  closet
//
//  Created by Dan Warner on 1/7/26.
//

import UIKit

extension UIImage {
    /// Compresses image to target file size (default ~200KB for detail views)
    func compressForStorage(maxFileSizeKB: Int = 200) -> Data? {
        var compression: CGFloat = 0.8
        var imageData = self.jpegData(compressionQuality: compression)
        
        // Iteratively reduce compression quality until we hit target size
        while let data = imageData,
              data.count > maxFileSizeKB * 1024,
              compression > 0.1 {
            compression -= 0.1
            imageData = self.jpegData(compressionQuality: compression)
        }
        
        return imageData
    }
    
    /// Resizes image to maximum dimension while maintaining aspect ratio
    func resizeForStorage(maxDimension: CGFloat = 1200) -> UIImage? {
        let currentMaxDimension = max(size.width, size.height)
        
        // If already smaller than max, return original
        guard currentMaxDimension > maxDimension else {
            return self
        }
        
        let scale = maxDimension / currentMaxDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        // Use high-quality rendering
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1.0
        format.preferredRange = .extended
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resizedImage = renderer.image { context in
            context.cgContext.interpolationQuality = .high
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage
    }
    
    /// Generates a thumbnail for grid views (default 300px)
    func generateThumbnail(size: CGFloat = 300) -> Data? {
        return self.resizeForStorage(maxDimension: size)?
            .jpegData(compressionQuality: 0.7)
    }
    
    /// Optimized processing: resize first, then compress
    /// This is more efficient than compressing a large image
    func processForStorage(maxDimension: CGFloat = 1200, maxFileSizeKB: Int = 200) -> Data? {
        // First resize to reduce pixel count
        guard let resized = self.resizeForStorage(maxDimension: maxDimension) else {
            return nil
        }
        
        // Then compress the resized image
        return resized.compressForStorage(maxFileSizeKB: maxFileSizeKB)
    }
}

