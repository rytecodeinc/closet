//
//  ImageQueueCoordinator.swift
//  closet
//
//  Created by Dan Warner on 1/7/26.
//

import SwiftUI
import UIKit

@MainActor
class ImageQueueCoordinator: ObservableObject {
    @Published private(set) var imageQueue: [UIImage] = []
    @Published private(set) var currentIndex: Int = 0
    @Published var currentCroppedImage: UIImage? = nil // Store the currently cropped image
    
    var hasMore: Bool { 
        currentIndex < imageQueue.count - 1 
    }
    
    var remainingCount: Int { 
        max(0, imageQueue.count - currentIndex - 1)
    }
    
    var currentImage: UIImage? { 
        guard currentIndex < imageQueue.count else { return nil }
        return imageQueue[currentIndex] 
    }
    
    var nextCroppedImage: UIImage? {
        return currentCroppedImage
    }
    
    var isQueueActive: Bool {
        !imageQueue.isEmpty
    }
    
    func loadQueue(_ images: [UIImage]) {
        self.imageQueue = images
        self.currentIndex = 0
        self.currentCroppedImage = nil
        print("📸 Queue loaded with \(images.count) images")
    }
    
    func storeCroppedImage(_ image: UIImage) {
        self.currentCroppedImage = image
        print("📸 Stored cropped image for index \(currentIndex)")
    }
    
    func moveToNext() {
        guard hasMore else {
            print("📸 ⚠️ moveToNext() called but no more images (currentIndex: \(currentIndex), count: \(imageQueue.count))")
            return
        }
        currentIndex += 1
        currentCroppedImage = nil // Clear the cropped image for next item
        print("📸 ✅ Moved to next image (currentIndex: \(currentIndex), remaining: \(remainingCount))")
    }
    
    func clear() {
        print("📸 Clearing queue (had \(imageQueue.count) images)")
        imageQueue.removeAll()
        currentIndex = 0
        currentCroppedImage = nil
    }
}

