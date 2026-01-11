//
//  VirtualFittingView.swift
//  closet
//
//  Created by Dan Warner on 1/7/26.
//

import CoreML
import SwiftUI
import StableDiffusion

/// iPhone 13 Pro (iOS 17.x) friendly:
/// - `reduceMemory: true` to lower peak RAM
/// - prefers Neural Engine compute units, falls back to GPU
/// - disables denoised-intermediate previews (they increase memory and UI churn)
struct VirtualFittingView: View {
    @State private var prompt: String = "a photo of a child looking at the stars"

    @State private var pipeline: StableDiffusionPipeline?
    @State private var isInitializing = true
    @State private var statusMessage: String?

    @State private var image: CGImage?
    @State private var progress: Double = 0.0
    @State private var isGenerating = false
    @State private var cancelRequested = false

    // Defaults aligned with the HF sample app (mobile-friendly)
    @State private var stepCount: Double = 25
    @State private var guidanceScale: Double = 7.5
    @State private var disableSafety = false

    var body: some View {
        VStack(spacing: 12) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Group {
                if let image {
                    Image(image, scale: 1.0, label: Text("Generated image"))
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.quaternary)
                        .overlay(Text("No image yet").foregroundStyle(.secondary))
                        .aspectRatio(1, contentMode: .fit)
                }
            }

            if isInitializing {
                ProgressView("Initializing…")
            } else if isGenerating {
                ProgressView(value: progress) {
                    Text("Generating (\(Int(progress * 100))%)")
                }
                Button("Cancel") {
                    cancelRequested = true
                }
                .buttonStyle(.bordered)
            } else {
                TextField("Prompt", text: $prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)

                HStack {
                    Text("Steps: \(Int(stepCount))")
                    Slider(value: $stepCount, in: 10...50, step: 1)
                }

                HStack {
                    Text("Guidance: \(guidanceScale, specifier: "%.1f")")
                    Slider(value: $guidanceScale, in: 0...12, step: 0.5)
                }

                Toggle("Disable Safety Checker", isOn: $disableSafety)

                Button("Generate") {
                    generateImage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pipeline == nil)
            }
        }
        .padding()
        .task {
            await initializePipelineIfNeeded()
        }
    }
}

private extension VirtualFittingView {
    enum VirtualFittingError: LocalizedError {
        case modelsFolderNotFound

        var errorDescription: String? {
            switch self {
            case .modelsFolderNotFound:
                return """
                Models folder not found in app bundle.

                Add a *folder reference* named “Models” to your app target containing:
                - TextEncoder.mlmodelc
                - Unet.mlmodelc
                - VAEDecoder.mlmodelc
                - (optional) SafetyChecker.mlmodelc
                - vocab.json + merges.txt
                """
            }
        }
    }

    func modelsURLFromBundle() throws -> URL {
        if let url = Bundle.main.url(forResource: "Models", withExtension: nil) {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("Models", isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        throw VirtualFittingError.modelsFolderNotFound
    }

    func makePipeline(modelsURL: URL, computeUnits: MLComputeUnits) throws -> StableDiffusionPipeline {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits

        // iPhone-friendly: keep reduceMemory on to lower peak RAM.
        let pipeline = try StableDiffusionPipeline(
            resourcesAt: modelsURL,
            controlNet: [],
            configuration: configuration,
            disableSafety: false,
            reduceMemory: true
        )
        try pipeline.loadResources()
        return pipeline
    }

    func initializePipelineIfNeeded() async {
        guard pipeline == nil else {
            isInitializing = false
            return
        }

        await MainActor.run {
            isInitializing = true
            statusMessage = "Loading diffusion pipeline…"
        }

        do {
            let modelsURL = try modelsURLFromBundle()

            // Prefer Neural Engine first (best case on iPhone 13 Pro), then fall back to GPU.
            let loaded = try await Task.detached(priority: .userInitiated) { () -> StableDiffusionPipeline in
                do {
                    return try makePipeline(modelsURL: modelsURL, computeUnits: .cpuAndNeuralEngine)
                } catch {
                    return try makePipeline(modelsURL: modelsURL, computeUnits: .cpuAndGPU)
                }
            }.value

            await MainActor.run {
                self.pipeline = loaded
                self.statusMessage = nil
                self.isInitializing = false
            }
        } catch {
            await MainActor.run {
                self.pipeline = nil
                self.statusMessage = "Pipeline init failed: \(error.localizedDescription)"
                self.isInitializing = false
            }
        }
    }

    func generateImage() {
        guard let pipeline else {
            statusMessage = "Pipeline not initialized."
            return
        }

        let currentPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentPrompt.isEmpty else { return }

        statusMessage = nil
        progress = 0
        image = nil
        isGenerating = true
        cancelRequested = false

        let steps = Int(stepCount)
        let guidance = Float(guidanceScale)
        let disableSafety = disableSafety

        Task.detached(priority: .userInitiated) {
            do {
                // Helps release temporary Obj-C objects sooner during heavy loops.
                let finalImage: CGImage? = try autoreleasepool {
                    var config = StableDiffusionPipeline.Configuration(prompt: currentPrompt)
                    config.stepCount = steps
                    config.guidanceScale = guidance
                    config.disableSafety = disableSafety

                    // Memory saver: don't keep denoised intermediates for previews.
                    // (HF sample sets previews=0 on iOS; this matches that intent.)
                    config.useDenoisedIntermediates = false

                    // Faster default in HF sample.
                    config.schedulerType = .dpmSolverMultistepScheduler

                    let images = try pipeline.generateImages(configuration: config) { progress in
                        Task { @MainActor in
                            let denom = Double(max(progress.stepCount, 1))
                            let step = Double(progress.step + 1)
                            self.progress = min(step / denom, 1.0)
                        }
                        return !cancelRequested
                    }

                    // nil means safety checker triggered
                    return images.compactMap { $0 }.first
                }

                await MainActor.run {
                    self.image = finalImage
                    self.isGenerating = false
                    if cancelRequested {
                        self.statusMessage = "Generation canceled."
                    } else if finalImage == nil {
                        self.statusMessage = "Safety checker blocked the output. Try a different prompt."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.statusMessage = "Generation failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
