//
//  DeepLinkManager.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import SwiftUI

class DeepLinkManager: ObservableObject {
    @Published var pendingURL: URL?
    @Published var pendingImage: UIImage?
    @Published var shouldPresentItemAdd = false
    
    func handleURL(_ url: URL) {
        print("🔗 DeepLinkManager: Received URL: \(url)")
        guard url.scheme == "closetapp",
              url.host == "additem",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("❌ Invalid deep link URL: \(url)")
            return
        }
        
        print("🔗 DeepLinkManager: Query items: \(queryItems.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", "))")
        
        // Ensure updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Handle image identifier (from Photos app or image sharing via UIPasteboard)
            if let imageIdItem = queryItems.first(where: { $0.name == "imageId" }),
               let imageIdentifier = imageIdItem.value {
                // Load image from pasteboard (shared between extension and main app)
                let pasteboard = UIPasteboard.general
                
                // Verify this is the image we just shared (check timestamp)
                if let lastSharedId = UserDefaults.standard.string(forKey: "lastSharedImageId"),
                   let lastTimestamp = UserDefaults.standard.object(forKey: "lastSharedImageTimestamp") as? TimeInterval,
                   lastSharedId == imageIdentifier,
                   Date().timeIntervalSince1970 - lastTimestamp < 10.0 { // Within 10 seconds
                    
                    // Get image from pasteboard
                    if let imageData = pasteboard.data(forPasteboardType: "public.jpeg"),
                       let image = UIImage(data: imageData) {
                        self.pendingImage = image
                        self.shouldPresentItemAdd = true
                        // Clean up
                        UserDefaults.standard.removeObject(forKey: "lastSharedImageId")
                        UserDefaults.standard.removeObject(forKey: "lastSharedImageTimestamp")
                        print("✅ DeepLinkManager: Loaded shared image from pasteboard with identifier: \(imageIdentifier)")
                        print("✅ DeepLinkManager: Set shouldPresentItemAdd = true, pendingImage set")
                        return
                    } else {
                        print("⚠️ DeepLinkManager: Could not load image data from pasteboard for identifier: \(imageIdentifier)")
                    }
                } else {
                    print("⚠️ DeepLinkManager: Image identifier mismatch or expired: \(imageIdentifier)")
                    if let lastSharedId = UserDefaults.standard.string(forKey: "lastSharedImageId") {
                        print("   Expected: \(lastSharedId), Got: \(imageIdentifier)")
                    }
                }
            }
        
            // Legacy: Handle image path (for backwards compatibility)
            if let imagePathItem = queryItems.first(where: { $0.name == "imagePath" }),
               let imagePath = imagePathItem.value?.removingPercentEncoding {
                // Load image from shared container file path
                let imageURL = URL(fileURLWithPath: imagePath)
                if let imageData = try? Data(contentsOf: imageURL),
                   let image = UIImage(data: imageData) {
                    self.pendingImage = image
                    self.shouldPresentItemAdd = true
                    // Clean up the shared file after loading
                    try? FileManager.default.removeItem(at: imageURL)
                    print("✅ DeepLinkManager: Loaded shared image from path: \(imagePath)")
                    return
                } else {
                    print("⚠️ DeepLinkManager: Could not load image from path: \(imagePath)")
                }
            }
            
            // Legacy: Handle image file URL (for backwards compatibility)
            if let imageItem = queryItems.first(where: { $0.name == "image" }),
               let imageURLString = imageItem.value,
               let imageURL = URL(string: imageURLString) {
                // Load image from file URL
                if imageURL.isFileURL {
                    if let imageData = try? Data(contentsOf: imageURL),
                       let image = UIImage(data: imageData) {
                        self.pendingImage = image
                        self.shouldPresentItemAdd = true
                        print("✅ DeepLinkManager: Loaded image from file URL: \(imageURL)")
                        return
                    }
                }
            }
            
            // Handle URL parameter (from Safari/browsers)
            if let urlItem = queryItems.first(where: { $0.name == "url" }),
               let urlString = urlItem.value,
               let sharedURL = URL(string: urlString) {
                self.pendingURL = sharedURL
                self.shouldPresentItemAdd = true
                print("✅ DeepLinkManager: Set pendingURL and shouldPresentItemAdd = true")
            }
        }
    }
    
    func clearPendingData() {
        pendingURL = nil
        pendingImage = nil
        shouldPresentItemAdd = false
    }
    
    // Legacy method for backwards compatibility
    func clearPendingURL() {
        clearPendingData()
    }
}

