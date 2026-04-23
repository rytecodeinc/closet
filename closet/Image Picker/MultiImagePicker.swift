//
//  MultiImagePicker.swift
//  closet
//
//  Created by Dan Warner on 1/7/26.
//

import SwiftUI
import PhotosUI

struct MultiImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    /// `0` = unlimited (PHPicker). Use `10` (etc.) to cap selection for bulk import.
    var selectionLimit: Int
    var onComplete: () -> Void

    init(selectedImages: Binding<[UIImage]>, selectionLimit: Int = 0, onComplete: @escaping () -> Void) {
        self._selectedImages = selectedImages
        self.selectionLimit = selectionLimit
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = selectionLimit
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePicker

        init(_ parent: MultiImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard !results.isEmpty else {
                parent.onComplete()
                return
            }

            let group = DispatchGroup()
            var images: [UIImage] = []

            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    defer { group.leave() }
                    if let image = object as? UIImage {
                        DispatchQueue.main.async {
                            images.append(image)
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                self.parent.selectedImages = images
                self.parent.onComplete()
            }
        }
    }
}
