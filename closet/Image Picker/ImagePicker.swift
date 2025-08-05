//
//  ImagePicker.swift
//  closet
//
//  Created by Dan Warner on 7/31/25.
//


import SwiftUI
import PhotosUI

import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType
    var allowsEditing: Bool
    var completionHandler: ((UIImage?) -> Void)?

    @Environment(\.presentationMode) private var presentationMode

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

import SwiftUI

struct ImageCropperView: View {
    let originalImage: UIImage
    let onCrop: (UIImage) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            ZStack {
                Color.white

                GeometryReader { geo in
                    Image(uiImage: originalImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    self.offset = gesture.translation
                                }
                        )
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    self.scale = max(1.0, value)
                                }
                        )
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .border(Color.black.opacity(0.2))
            }
        }
        .navigationTitle("Crop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    cropAndSaveImage()
                }
            }
        }
    }

    func cropAndSaveImage() {
        let size = CGSize(width: 1080, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)
        let newImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let imageSize = originalImage.size
            let imageScale = min(size.width / imageSize.width, size.height / imageSize.height) * scale

            let scaledSize = CGSize(width: imageSize.width * imageScale, height: imageSize.height * imageScale)
            let origin = CGPoint(
                x: (size.width - scaledSize.width) / 2 + offset.width,
                y: (size.height - scaledSize.height) / 2 + offset.height
            )

            originalImage.draw(in: CGRect(origin: origin, size: scaledSize))
        }

        onCrop(newImage)
        dismiss()
    }
}
