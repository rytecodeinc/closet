//
//  ShareableItem.swift
//  closet
//
//  Created by Dan Warner on 12/6/25.
//


import SwiftUI
import UniformTypeIdentifiers

struct ShareableItem: Transferable {
    let text: String
    let image: UIImage?

    static var transferRepresentation: some TransferRepresentation {
        // 1. Export text as plain text
        DataRepresentation(exportedContentType: .plainText) { item in
            item.text.data(using: .utf8) ?? Data()
        }
        
        // 2. Export image as PNG
        DataRepresentation(exportedContentType: .png) { item in
            item.image?.pngData() ?? Data()
        }

        /* Share the image too (optional)
        if #available(iOS 17.0, *) {
            ProxyRepresentation(exporting: \.image)
        }*/
    }
}
