//
//  ShareViewController.swift
//  AppShareExtension
//
//  Created by Dan Warner on 10/9/25.
//

// MARK: - 1. ShareViewController.swift (in AppShareExtension target)
import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Hide the view immediately - we don't need to show any UI
        view.isHidden = true
        handleSharedContent()
    }
    
    private func handleSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments,
              !attachments.isEmpty else {
            print("⚠️ Share extension: No attachments found")
            completeRequest()
            return
        }
        
        // Debug: Log all available type identifiers
        for (index, itemProvider) in attachments.enumerated() {
            print("📋 Share extension: Attachment \(index) - registered types: \(itemProvider.registeredTypeIdentifiers)")
        }
        
        // Process all attachments - prioritize images, then URLs
        // Check each attachment for supported types
        for itemProvider in attachments {
            // 1. Check for images (from Photos, Safari, Messages, Depop, etc.)
            // Check multiple image type identifiers to support all apps
            let imageTypeIdentifiers = [
                UTType.image.identifier,
                UTType.jpeg.identifier,
                UTType.png.identifier,
                UTType.heic.identifier,
                UTType.heif.identifier,
                UTType.gif.identifier,
                "public.image",
                "public.jpeg",
                "public.png",
                "public.heic",
                "public.heif",
                "com.compuserve.gif"
            ]
            
            var foundImageType: String?
            for typeIdentifier in imageTypeIdentifiers {
                if itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                    foundImageType = typeIdentifier
                    break
                }
            }
            
            if let imageType = foundImageType {
                print("📸 Share extension: Detected image type: \(imageType)")
                itemProvider.loadItem(forTypeIdentifier: imageType, options: nil) { [weak self] (item, error) in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("❌ Share extension: Error loading image: \(error.localizedDescription)")
                        self.completeRequest()
                        return
                    }
                    
                    print("📸 Share extension: Image item type: \(type(of: item))")
                    
                    if let image = item as? UIImage {
                        print("✅ Share extension: Received UIImage directly")
                        self.openMainApp(withImage: image)
                    } else if let imageURL = item as? URL {
                        // Image file URL (common from Photos app)
                        print("✅ Share extension: Received image file URL: \(imageURL)")
                        // Try to access the file URL directly - Photos often provides accessible URLs
                        if imageURL.startAccessingSecurityScopedResource() {
                            defer { imageURL.stopAccessingSecurityScopedResource() }
                            
                            if let imageData = try? Data(contentsOf: imageURL),
                               let image = UIImage(data: imageData) {
                                print("✅ Share extension: Loaded image from file URL")
                                self.openMainApp(withImage: image)
                            } else {
                                print("❌ Share extension: Failed to load image data from URL")
                                self.completeRequest()
                            }
                        } else {
                            print("❌ Share extension: Could not access security-scoped resource")
                            self.completeRequest()
                        }
                    } else if let imageData = item as? Data {
                        print("✅ Share extension: Received image as Data")
                        if let image = UIImage(data: imageData) {
                            self.openMainApp(withImage: image)
                        } else {
                            print("❌ Share extension: Failed to create UIImage from Data")
                            self.completeRequest()
                        }
                    } else {
                        print("❌ Share extension: Unknown image item type: \(type(of: item))")
                        self.completeRequest()
                    }
                }
                return // Found image, process it and return
            }
        }
        
        // 2. If no images found, check for URLs (from Safari, browsers, etc.)
        for itemProvider in attachments {
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                    guard let self = self else { return }
                    
                    var sharedURL: URL?
                    
                    if let url = item as? URL {
                        sharedURL = url
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        sharedURL = url
                    }
                    
                    if let url = sharedURL {
                        self.openMainApp(with: url)
                    } else {
                        self.completeRequest()
                    }
                }
                return // Found URL, process it and return
            }
        }
        
        // No supported content found
        print("⚠️ Share extension: No supported content type found")
        completeRequest()
    }
    
    /// Opens main app with a URL
    private func openMainApp(with url: URL) {
        let encodedURL = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let appURLString = "closetapp://additem?url=\(encodedURL)"
        
        guard let deepLinkURL = URL(string: appURLString) else {
            completeRequest()
            return
        }
        
        openURL(deepLinkURL)
    }
    
    /// Opens main app with an image
    private func openMainApp(withImage image: UIImage) {
        // Use UIPasteboard to share image data (accessible by both extension and main app)
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert image to JPEG data")
            completeRequest()
            return
        }
        
        // Save image to pasteboard
        let pasteboard = UIPasteboard.general
        pasteboard.setData(imageData, forPasteboardType: "public.jpeg")
        print("📸 Share extension: Saved image data to pasteboard (\(imageData.count) bytes)")
        
        // Open main app via deep link
        let appURLString = "closetapp://additem?image=true"
        
        guard let deepLinkURL = URL(string: appURLString) else {
            print("❌ Failed to create deep link URL")
            completeRequest()
            return
        }
        
        print("✅ Share extension: Opening main app with image")
        openURL(deepLinkURL)
    }
    
    /// Helper to open URL using responder chain
    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while responder != nil {
            if responder!.responds(to: Selector(("openURL:"))) {
                responder!.perform(Selector(("openURL:")), with: url)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.completeRequest()
                }
                return
            }
            responder = responder?.next
        }
        completeRequest()
    }
    
    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
