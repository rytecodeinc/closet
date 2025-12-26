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
        handleSharedContent()
    }
    
    private func handleSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            completeRequest()
            return
        }
        
        // Check for URL
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
        } else {
            completeRequest()
        }
    }
    
    private func openMainApp(with url: URL) {
        // Create URL scheme to open main app
        // Format: closetapp://additem?url=<encoded_url>
        let encodedURL = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let appURL = "closetapp://additem?url=\(encodedURL)"
        
        guard let deepLinkURL = URL(string: appURL) else {
            completeRequest()
            return
        }
        
        // Open the main app using the shared app group's UIResponder
        var responder: UIResponder? = self as UIResponder
        let selector = #selector(openURL(_:))
        
        while responder != nil {
            if responder!.responds(to: selector) && responder != self {
                responder!.perform(selector, with: deepLinkURL)
                break
            }
            responder = responder?.next
        }
        
        // Complete the extension request
        completeRequest()
    }
    
    @objc private func openURL(_ url: URL) {
        // This method will be called on UIApplication via the responder chain
    }
    
    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
