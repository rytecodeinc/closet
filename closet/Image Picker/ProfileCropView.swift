//
//  ProfileCropView.swift
//  closet
//
//  Circular crop UI for profile avatars (pan / pinch / rotate only).
//

import SwiftUI
import UIKit

struct ProfileCropView: View {
    let originalImage: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: (() -> Void)?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var cropViewSize: CGSize = .zero

    @Environment(\.dismiss) private var dismiss

    init(
        originalImage: UIImage,
        onCrop: @escaping (UIImage) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.originalImage = originalImage
        self.onCrop = onCrop
        self.onCancel = onCancel
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    Color.black.opacity(0.08)

                    Image(uiImage: originalImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(scale)
                        .rotationEffect(rotation)
                        .offset(offset)
                        .frame(width: side, height: side)
                        .clipped()
                        .gesture(transformGestures)

                    circularCropOverlay(side: side)
                }
                .frame(width: side, height: side)
                .clipShape(Rectangle())
                .onAppear {
                    cropViewSize = CGSize(width: side, height: side)
                }
                .onChange(of: geo.size) { _, newSize in
                    let s = min(newSize.width, newSize.height)
                    cropViewSize = CGSize(width: s, height: s)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Crop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if let onCancel {
                        onCancel()
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    cropAndSaveImage()
                }
                .fontWeight(.semibold)
            }
        }
    }

    /// Dims everything outside the circle so the user sees the avatar framing.
    private func circularCropOverlay(side: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(width: side, height: side)
                .overlay {
                    Circle()
                        .frame(width: side, height: side)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

            Circle()
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    private var transformGestures: some Gesture {
        SimultaneousGesture(
            SimultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if !isDragging {
                            lastOffset = offset
                            isDragging = true
                        }
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                        isDragging = false
                    },
                MagnificationGesture()
                    .onChanged { value in
                        scale = lastScale * value
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            ),
            RotationGesture()
                .onChanged { value in
                    rotation = lastRotation + value
                }
                .onEnded { _ in
                    lastRotation = rotation
                }
        )
    }

    private func cropAndSaveImage() {
        let canvasSize = cropViewSize
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

        let side = canvasSize.width
        let captureView = ZStack {
            Color.clear
            Image(uiImage: originalImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(scale)
                .rotationEffect(rotation)
                .offset(offset)
                .frame(width: side, height: side)
                .clipped()
        }
        .frame(width: side, height: side)

        let renderer = ImageRenderer(content: captureView)
        renderer.isOpaque = false
        renderer.scale = UIScreen.main.scale

        guard let croppedImage = renderer.uiImage else { return }
        onCrop(croppedImage)
        dismiss()
    }
}
