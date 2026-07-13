//
//  DeepLinkRouter.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import SwiftUI
import UIKit

/// Centralized deep link router that handles navigation intents
class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    
    @Published var navigationIntent: NavigationIntent?

    /// Set when the user taps an APNs notification; ContentView switches to Profile and ProfileView presents the list.
    @Published var shouldOpenNotifications = false
    
    private init() {}

    func openNotificationsFromPush() {
        DispatchQueue.main.async { [weak self] in
            self?.shouldOpenNotifications = true
        }
    }

    func consumeOpenNotifications() {
        shouldOpenNotifications = false
    }
    
    /// Processes incoming deep link URL and stores navigation intent
    func handleURL(_ url: URL) {
        print("🔗 DeepLinkRouter: Received URL: \(url)")
        
        guard url.scheme == "closetapp",
              url.host == "additem",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("❌ DeepLinkRouter: Invalid deep link URL: \(url)")
            return
        }
        
        print("🔗 DeepLinkRouter: Query items: \(queryItems.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", "))")
        
        // Process on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Handle image from pasteboard (from Photos app or image sharing)
            if let imageItem = queryItems.first(where: { $0.name == "image" }),
               imageItem.value == "true" {
                self.handleImageIntent()
                return
            }
            
            // Handle image identifier (legacy support)
            if let imageIdItem = queryItems.first(where: { $0.name == "imageId" }),
               imageIdItem.value != nil {
                self.handleImageIntent()
                return
            }
            
            // Handle image path (legacy)
            if let imagePathItem = queryItems.first(where: { $0.name == "imagePath" }),
               let imagePath = imagePathItem.value?.removingPercentEncoding {
                self.handleImagePathIntent(imagePath: imagePath)
                return
            }
            
            // Handle image file URL (legacy)
            if let imageItem = queryItems.first(where: { $0.name == "image" }),
               let imageURLString = imageItem.value,
               let imageURL = URL(string: imageURLString) {
                if imageURL.isFileURL {
                    self.handleImageURLIntent(imageURL: imageURL)
                    return
                }
            }
            
            // Handle URL parameter (from Safari/browsers)
            if let urlItem = queryItems.first(where: { $0.name == "url" }),
               let urlString = urlItem.value,
               let sharedURL = URL(string: urlString) {
                self.handleURLIntent(url: sharedURL)
                return
            }
        }
    }
    
    // MARK: - Intent Handlers
    
    private func handleImageIntent() {
        print("📸 DeepLinkRouter: Handling image intent")
        
        // Load image from pasteboard (shared between extension and app)
        let pasteboard = UIPasteboard.general
        
        if let imageData = pasteboard.data(forPasteboardType: "public.jpeg"),
           let image = UIImage(data: imageData) {
            // Store navigation intent
            navigationIntent = .addItem(image: image, url: nil)
            print("✅ DeepLinkRouter: Set navigation intent with image from pasteboard")
            return
        } else {
            print("⚠️ DeepLinkRouter: Could not load image data from pasteboard")
            // Check what types are available for debugging
            print("📋 DeepLinkRouter: Available pasteboard types: \(pasteboard.types)")
        }
        
        // If we get here, image loading failed
        navigationIntent = nil
        print("❌ DeepLinkRouter: Failed to load image, navigation intent set to nil")
    }
    
    private func handleImagePathIntent(imagePath: String) {
        print("📸 DeepLinkRouter: Handling image path intent: \(imagePath)")
        let imageURL = URL(fileURLWithPath: imagePath)
        
        if let imageData = try? Data(contentsOf: imageURL),
           let image = UIImage(data: imageData) {
            // Clean up
            try? FileManager.default.removeItem(at: imageURL)
            navigationIntent = .addItem(image: image, url: nil)
            print("✅ DeepLinkRouter: Set navigation intent with image from path")
        } else {
            print("⚠️ DeepLinkRouter: Could not load image from path")
            navigationIntent = nil
        }
    }
    
    private func handleImageURLIntent(imageURL: URL) {
        print("📸 DeepLinkRouter: Handling image URL intent: \(imageURL)")
        
        if let imageData = try? Data(contentsOf: imageURL),
           let image = UIImage(data: imageData) {
            navigationIntent = .addItem(image: image, url: nil)
            print("✅ DeepLinkRouter: Set navigation intent with image from URL")
        } else {
            print("⚠️ DeepLinkRouter: Could not load image from URL")
            navigationIntent = nil
        }
    }
    
    private func handleURLIntent(url: URL) {
        print("🔗 DeepLinkRouter: Handling URL intent: \(url)")
        navigationIntent = .addItem(image: nil, url: url)
        print("✅ DeepLinkRouter: Set navigation intent with URL")
    }
    
    /// Clears the current navigation intent
    func clearIntent() {
        navigationIntent = nil
    }
}

// MARK: - Navigation Intent

enum NavigationIntent: Equatable {
    case addItem(image: UIImage?, url: URL?)
    
    // Custom Equatable implementation since UIImage isn't Equatable
    // We compare by URL and image presence, not actual image data
    static func == (lhs: NavigationIntent, rhs: NavigationIntent) -> Bool {
        switch (lhs, rhs) {
        case (.addItem(let lhsImage, let lhsURL), .addItem(let rhsImage, let rhsURL)):
            // Compare URLs and image presence (not actual image data)
            return lhsURL == rhsURL && (lhsImage != nil) == (rhsImage != nil)
        }
    }
    
    var hasImage: Bool {
        switch self {
        case .addItem(let image, _):
            return image != nil
        }
    }
    
    var url: URL? {
        switch self {
        case .addItem(_, let url):
            return url
        }
    }
    
    var image: UIImage? {
        switch self {
        case .addItem(let image, _):
            return image
        }
    }
}

