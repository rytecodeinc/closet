//
//  BulkCameraImportFlowView.swift
//  closet
//
//  Add Multiple → From Camera: square multi-capture with inline thumbnails → bulk import.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Flow container

struct BulkCameraImportFlowView: View {
    static let maxPhotoCount = 10

    @State private var capturedPhotos: [QueuedCapture] = []

    var onAdd: ([UIImage]) -> Void
    var onCancel: () -> Void

    var body: some View {
        BulkCameraCaptureView(
            capturedPhotos: $capturedPhotos,
            maxCount: Self.maxPhotoCount,
            onAdd: { onAdd(capturedPhotos.map(\.image)) },
            onCancel: {
                capturedPhotos.removeAll()
                onCancel()
            }
        )
    }
}

// MARK: - Combined capture + review

private struct QueuedCapture: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct BulkCameraCaptureView: View {
    @Binding var capturedPhotos: [QueuedCapture]
    let maxCount: Int
    var onAdd: () -> Void
    var onCancel: () -> Void

    private enum Layout {
        static let shutterOuterPadding: CGFloat = 20
        static let shutterDiameter: CGFloat = 74
        static var shutterBandHeight: CGFloat {
            shutterOuterPadding * 2 + shutterDiameter
        }
    }

    @StateObject private var camera = MultiCaptureCameraModel()
    @State private var isCapturing = false
    @State private var isLiveCamera = true
    @State private var selectedIndex = 0
    @State private var showDiscardConfirmation = false

    private var atMax: Bool { capturedPhotos.count >= maxCount }
    private var showsCameraInViewport: Bool {
        isLiveCamera && !atMax && !camera.cameraAccessDenied
    }
    private var showsShutter: Bool {
        showsCameraInViewport && camera.isConfigured
    }
    private var showsCameraReturnTile: Bool {
        !atMax && !isLiveCamera && !capturedPhotos.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    Text("\(capturedPhotos.count)/\(maxCount)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.bottom, 10)

                    squareViewport

                    shutterBand
                        .frame(height: Layout.shutterBandHeight)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                thumbnailStrip
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(UIColor.secondarySystemBackground)
                            .ignoresSafeArea(edges: .bottom)
                    )
            }
            .navigationTitle("Capture Multiple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: handleCancelTapped)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: onAdd)
                        .fontWeight(.semibold)
                        .disabled(capturedPhotos.isEmpty)
                }
            }
        }
        .alert("Discard photos?", isPresented: $showDiscardConfirmation) {
            Button("Discard All", role: .destructive, action: onCancel)
            Button("Keep Capturing", role: .cancel) {}
        } message: {
            Text("This will discard all images you have captured.")
        }
        .onAppear { camera.prepare() }
        .onDisappear { camera.stopSession() }
        .onChange(of: isLiveCamera) { _, live in
            if live, !atMax {
                camera.startSession()
            } else {
                camera.stopSession()
            }
        }
        .onChange(of: atMax) { _, maxed in
            if maxed {
                camera.stopSession()
                selectedIndex = 0
            } else if isLiveCamera {
                camera.startSession()
            }
        }
    }

    private var squareViewport: some View {
        GeometryReader { geo in
            let side = geo.size.width

            previewContent
                .frame(width: side, height: side)
                .clipped()
                .frame(width: side, height: side, alignment: .top)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var previewContent: some View {
        if camera.cameraAccessDenied {
            accessDeniedContent
        } else if showsCameraInViewport {
            if camera.isConfigured {
                CameraPreviewRepresentable(session: camera.session)
            } else {
                ProgressView()
                    .tint(.white)
            }
        } else if isLiveCamera, atMax, let first = capturedPhotos.first {
            Image(uiImage: first.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        } else if !isLiveCamera, !capturedPhotos.isEmpty {
            TabView(selection: $selectedIndex) {
                ForEach(Array(capturedPhotos.enumerated()), id: \.element.id) { index, capture in
                    Image(uiImage: capture.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        } else {
            Color.black
        }
    }

    private var accessDeniedContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
            Text("Camera access is required to take photos.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .foregroundStyle(.white)
    }

    private var shutterBand: some View {
        ZStack {
            if showsShutter {
                shutterControl
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shutterControl: some View {
        Button(action: capturePhoto) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(.white)
                    .frame(width: 62, height: 62)
                    .opacity(atMax || isCapturing ? 0.35 : 1)
            }
        }
        .disabled(atMax || isCapturing || !camera.isConfigured || camera.cameraAccessDenied)
        .accessibilityLabel("Take photo")
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(capturedPhotos.enumerated()), id: \.element.id) { index, capture in
                        thumbnailCell(capture: capture, index: index)
                            .id(capture.id)
                    }
                    if showsCameraReturnTile {
                        cameraReturnTile
                            .id("camera-return")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(minHeight: 88)
            .onChange(of: capturedPhotos.count) { _, count in
                guard count > 0, let last = capturedPhotos.last else { return }
                withAnimation {
                    proxy.scrollTo(last.id, anchor: .trailing)
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                guard !isLiveCamera, capturedPhotos.indices.contains(newIndex) else { return }
                withAnimation {
                    proxy.scrollTo(capturedPhotos[newIndex].id, anchor: .center)
                }
            }
        }
    }

    private func thumbnailCell(capture: QueuedCapture, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                selectedIndex = index
                isLiveCamera = false
            } label: {
                Image(uiImage: capture.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                !isLiveCamera && selectedIndex == index ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    }
            }
            .buttonStyle(.plain)

            Button {
                removePhoto(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .buttonStyle(.borderless)
            .offset(x: 6, y: -6)
            .zIndex(1)
            .accessibilityLabel("Remove photo")
        }
    }

    private var cameraReturnTile: some View {
        Button(action: resumeCamera) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                Text("Camera")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.primary)
            .frame(width: 64, height: 64)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Return to camera")
    }

    private func capturePhoto() {
        guard !atMax, !isCapturing else { return }
        isCapturing = true
        camera.capturePhoto { image in
            isCapturing = false
            guard let image else { return }
            capturedPhotos.append(QueuedCapture(image: image.centerSquareCropped()))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func removePhoto(at index: Int) {
        guard capturedPhotos.indices.contains(index) else { return }
        capturedPhotos.remove(at: index)
        if capturedPhotos.isEmpty {
            resumeCamera()
        } else if !isLiveCamera {
            selectedIndex = min(index, capturedPhotos.count - 1)
        }
    }

    private func handleCancelTapped() {
        if capturedPhotos.isEmpty {
            onCancel()
        } else {
            showDiscardConfirmation = true
        }
    }

    private func resumeCamera() {
        isLiveCamera = true
        camera.startSession()
    }
}

// MARK: - Camera session

@MainActor
private final class MultiCaptureCameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var isConfigured = false
    @Published private(set) var cameraAccessDenied = false

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.closet.multicapture.session")
    private var captureCompletion: ((UIImage?) -> Void)?

    func prepare() {
        Task {
            let granted = await Self.requestCameraAccess()
            guard granted else {
                cameraAccessDenied = true
                return
            }
            configureSession()
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.inputs.isEmpty else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else {
                Task { @MainActor in completion(nil) }
                return
            }

            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }

            self.captureCompletion = completion
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                Task { @MainActor in self.cameraAccessDenied = true }
                return
            }
            self.session.addInput(input)

            guard self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                Task { @MainActor in self.cameraAccessDenied = true }
                return
            }
            self.session.addOutput(self.photoOutput)
            self.session.commitConfiguration()

            Task { @MainActor in
                self.isConfigured = true
                self.startSession()
            }
        }
    }

    private static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

extension MultiCaptureCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage?
        if error == nil,
           let data = photo.fileDataRepresentation(),
           let uiImage = UIImage(data: data) {
            image = uiImage
        } else {
            image = nil
        }
        Task { @MainActor [weak self] in
            self?.captureCompletion?(image)
            self?.captureCompletion = nil
        }
    }
}

private struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        uiView.setNeedsLayout()
    }
}

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        updatePreviewOrientation()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updatePreviewOrientation()
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer.connection else { return }
        let angle = Self.videoRotationAngle(for: window)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    /// Back-camera preview rotation for the current interface orientation.
    private static func videoRotationAngle(for window: UIWindow?) -> CGFloat {
        switch window?.windowScene?.interfaceOrientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        default: return 90
        }
    }
}

// MARK: - Square crop

private extension UIImage {
    func centerSquareCropped() -> UIImage {
        guard size.width > 0, size.height > 0 else { return self }
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            draw(in: CGRect(x: -origin.x, y: -origin.y, width: size.width, height: size.height))
        }
    }
}
