//
//  SingleItemLibraryPickAndCropSheet.swift
//  closet
//
//  Single-item Add → Choose from Library: library picker and crop in one sheet.
//  Navigation back from crop returns to the library; library Cancel dismisses the sheet.
//

import SwiftUI
import PhotosUI
import UIKit

struct SingleItemLibraryPickAndCropSheet: View {
    var onCropped: (UIImage) -> Void
    var onLibraryCancel: () -> Void

    @State private var cropCandidate: CropCandidate?

    var body: some View {
        NavigationStack {
            SingleImageLibraryPicker(
                onPick: { image in
                    cropCandidate = CropCandidate(image: image)
                },
                onCancel: onLibraryCancel
            )
            .navigationDestination(item: $cropCandidate) { candidate in
                ImageCropperView(
                    originalImage: candidate.image,
                    onCrop: { croppedImage in
                        onCropped(croppedImage)
                    },
                    showsCancelButton: false
                )
            }
        }
    }
}

private struct CropCandidate: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage

    static func == (lhs: CropCandidate, rhs: CropCandidate) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct SingleImageLibraryPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SingleImageLibraryPicker

        init(_ parent: SingleImageLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.onCancel()
                return
            }

            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        self.parent.onPick(image)
                    } else {
                        self.parent.onCancel()
                    }
                }
            }
        }
    }
}
