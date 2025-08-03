//
//  ImagePicker.swift
//  closet
//
//  Created by Dan Warner on 7/31/25.
//


import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType
    var allowsEditing: Bool
    
    var completionHandler: ((UIImage?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()

        picker.sourceType = sourceType // camera or library
        picker.allowsEditing = allowsEditing // scaling and cropping
        picker.delegate = context.coordinator

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let uiImage: UIImage?

            if parent.allowsEditing {
                uiImage = info[.editedImage] as? UIImage
            } else {
                uiImage = info[.originalImage] as? UIImage
            }

            parent.image = uiImage
            parent.completionHandler?(uiImage)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
