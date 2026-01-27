//
//  VirtualFittingView.swift
//  closet
//
//  Created by Dan Warner on 1/27/26.
//

import SwiftUI
import PhotosUI
import ImagePlayground
import UIKit

struct VirtualFittingView: View {
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    @State private var facePickerItem: PhotosPickerItem?
    @State private var bodyPickerItem: PhotosPickerItem?
    @State private var garmentPickerItem: PhotosPickerItem?

    // TODO: Persist face/body privately on-device (e.g., encrypted file storage).
    @State private var faceImage: UIImage?
    @State private var bodyImage: UIImage?
    // TODO: Replace with Item Photo (Photo.data) when closet integration is ready.
    @State private var garmentImage: UIImage?

    @State private var generatedImage: UIImage?
    @State private var promptText = ""
    @State private var isShowingPlayground = false

    private let compositeWidth: CGFloat = 1024
    private let faceHeight: CGFloat = 320
    private let bodyHeight: CGFloat = 640
    private let garmentHeight: CGFloat = 320

    private var canGenerate: Bool {
        faceImage != nil && bodyImage != nil && garmentImage != nil
    }

    private var compositeSourceImage: Image? {
        guard let faceImage, let bodyImage, let garmentImage else { return nil }
        let composite = buildCompositeReferenceImage(face: faceImage, body: bodyImage, garment: garmentImage)
        return Image(uiImage: composite)
    }

    private var basePrompt: String {
        "Use the face from the top panel, the body from the middle panel for proportions, and the clothing from the bottom panel. Keep the fit realistic and preserve the garment's details."
    }

    private var finalPrompt: String {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return basePrompt }
        return "\(basePrompt) \(trimmed)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                faceSection
                bodySection
                garmentSection
                promptSection
                generateSection
                resultSection
            }
            .padding()
        }
        .navigationTitle("Virtual Fitting")
        .imagePlaygroundSheet(
            isPresented: $isShowingPlayground,
            concept: finalPrompt,
            sourceImage: compositeSourceImage
        ) { url in
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                generatedImage = image
            }
        } onCancellation: {
            isShowingPlayground = false
        }
        .onChange(of: facePickerItem) { newItem in
            loadImage(from: newItem) { image in
                faceImage = image
                generatedImage = nil
            }
        }
        .onChange(of: bodyPickerItem) { newItem in
            loadImage(from: newItem) { image in
                bodyImage = image
                generatedImage = nil
            }
        }
        .onChange(of: garmentPickerItem) { newItem in
            loadImage(from: newItem) { image in
                garmentImage = image
                generatedImage = nil
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provide three references")
                .font(.title2.weight(.semibold))
            Text("Add a face, a full-body shot, and a garment image. Image Playground will blend them into a realistic try-on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var faceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1) Face (profile)")
                .font(.headline)
            Text("Front-facing or slight angle, good lighting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $facePickerItem, matching: .images) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .systemGray6))
                        .frame(width: 180, height: 180)
                        .overlay(
                            Circle().stroke(Color(uiColor: .systemGray4), lineWidth: 1)
                        )

                    if let faceImage {
                        Image(uiImage: faceImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 180, height: 180)
                            .clipShape(Circle())
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 42))
                                .foregroundStyle(.secondary)
                            Text("Select face")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("2) Body (proportions)")
                .font(.headline)
            Text("Full-body image for sizing and posture.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $bodyPickerItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .systemGray6))
                        .frame(height: 320)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(uiColor: .systemGray4), lineWidth: 1)
                        )

                    if let bodyImage {
                        Image(uiImage: bodyImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 320)
                            .clipped()
                            .cornerRadius(16)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "figure.stand")
                                .font(.system(size: 42))
                                .foregroundStyle(.secondary)
                            Text("Select body")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var garmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("3) Clothing (try-on)")
                .font(.headline)
            Text("Flat lay or product photo works best.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $garmentPickerItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .systemGray6))
                        .frame(height: 220)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(uiColor: .systemGray4), lineWidth: 1)
                        )

                    if let garmentImage {
                        Image(uiImage: garmentImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipped()
                            .cornerRadius(16)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "tshirt")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Select clothing")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try-on details (optional)")
                .font(.headline)
            TextField("Add style or fit notes", text: $promptText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !supportsImagePlayground {
                Text("Image Playground is unavailable on this device.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                isShowingPlayground = true
            } label: {
                Label("Generate try-on", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!supportsImagePlayground || !canGenerate)

            if !canGenerate {
                Text("Add all three images to enable generation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let generatedImage {
            VStack(alignment: .leading, spacing: 8) {
                Text("Result")
                    .font(.headline)
                Image(uiImage: generatedImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(16)
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?, assignTo setter: @escaping (UIImage?) -> Void) {
        guard let item else { return }
        Task {
            let image = await loadImage(from: item)
            await MainActor.run {
                setter(image)
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem) async -> UIImage? {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                return UIImage(data: data)
            }
        } catch {
            print("Failed to load photo picker image: \(error.localizedDescription)")
        }
        return nil
    }

    private func buildCompositeReferenceImage(face: UIImage, body: UIImage, garment: UIImage) -> UIImage {
        let totalHeight = faceHeight + bodyHeight + garmentHeight
        let size = CGSize(width: compositeWidth, height: totalHeight)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let fullRect = CGRect(origin: .zero, size: size)
            UIColor.white.setFill()
            context.fill(fullRect)

            let faceRect = CGRect(x: 0, y: 0, width: compositeWidth, height: faceHeight)
            let bodyRect = CGRect(x: 0, y: faceHeight, width: compositeWidth, height: bodyHeight)
            let garmentRect = CGRect(x: 0, y: faceHeight + bodyHeight, width: compositeWidth, height: garmentHeight)

            drawAspectFit(face, in: faceRect)
            drawAspectFit(body, in: bodyRect)
            drawAspectFit(garment, in: garmentRect)

            drawDivider(in: context.cgContext, y: faceHeight)
            drawDivider(in: context.cgContext, y: faceHeight + bodyHeight)
        }
    }

    private func drawAspectFit(_ image: UIImage, in rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: rect.midX - scaledSize.width / 2,
            y: rect.midY - scaledSize.height / 2
        )
        image.draw(in: CGRect(origin: origin, size: scaledSize))
    }

    private func drawDivider(in context: CGContext, y: CGFloat) {
        context.setFillColor(UIColor.systemGray4.cgColor)
        context.fill(CGRect(x: 0, y: y - 1, width: compositeWidth, height: 2))
    }
}

#Preview {
    VirtualFittingView()
}
