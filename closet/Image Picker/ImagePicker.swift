//
//  ImagePicker.swift
//  closet
//
//  Created by Dan Warner on 7/31/25.
//


import SwiftUI
import PhotosUI
import UIKit

import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var sourceType: UIImagePickerController.SourceType
    var allowsEditing: Bool
    /// When true, the picked image is passed to `completionHandler` directly after dismiss (no second full-screen crop UI).
    var skipEmbeddedCrop: Bool
    var completionHandler: ((UIImage?) -> Void)?

    @Environment(\.presentationMode) private var presentationMode

    init(
        image: Binding<UIImage?>,
        sourceType: Binding<UIImagePickerController.SourceType>,
        allowsEditing: Bool,
        skipEmbeddedCrop: Bool = false,
        completionHandler: ((UIImage?) -> Void)? = nil
    ) {
        _image = image
        _sourceType = sourceType
        self.allowsEditing = allowsEditing
        self.skipEmbeddedCrop = skipEmbeddedCrop
        self.completionHandler = completionHandler
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false // We’ll handle cropping manually
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let originalImage = info[.originalImage] as? UIImage else {
                picker.dismiss(animated: true)
                return
            }

            if parent.skipEmbeddedCrop {
                picker.dismiss(animated: true) {
                    DispatchQueue.main.async {
                        self.parent.image = originalImage
                        self.parent.completionHandler?(originalImage)
                    }
                }
                return
            }

            picker.dismiss(animated: true) {
                let cropper = NavigationStack {
                    ImageCropperView(
                        originalImage: originalImage,
                        onCrop: { croppedImage in
                            self.parent.image = croppedImage
                            self.parent.completionHandler?(croppedImage)
                        }
                    )
                }

                if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                    let hosting = UIHostingController(rootView: cropper)
                    hosting.modalPresentationStyle = .fullScreen
                    rootVC.present(hosting, animated: true)
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

