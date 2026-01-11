//
//  StableDiffusionService.swift
//  closet
//
//  Created by Dan Warner on 1/7/26.
//

import Foundation
import StableDiffusion
import CoreML
import UIKit

@MainActor
final class StableDiffusionService: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var generatedImage: UIImage?
    @Published var isPipelineReady: Bool = false
    @Published var generationProgress: Double = 0.0

    private var pipeline: StableDiffusionPipeline?
    private var isUnloading = false

    init() {
        // Don't load pipeline automatically
    }

    func loadPipeline() async throws {
        guard pipeline == nil, !isUnloading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Find the Models directory in the bundle
        guard let resourceURL = findModelResources() else {
            let error = NSError(
                domain: "StableDiffusionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model resources not found. Please ensure the Models folder (containing TextEncoder.mlmodelc, Unet.mlmodelc, VAEDecoder.mlmodelc, VAEEncoder.mlmodelc, vocab.json, and merges.txt) is included in the app bundle."]
            )
            throw error
        }

        let modelConfig = MLModelConfiguration()
        // **Key change: force CPU only**
        modelConfig.computeUnits = .cpuOnly

        do {
            pipeline = try StableDiffusionPipeline(
                resourcesAt: resourceURL,
                controlNet: [],
                configuration: modelConfig,
                disableSafety: false,
                reduceMemory: true
            )
            try pipeline?.loadResources()
            isPipelineReady = true
            print("✅ Stable Diffusion pipeline loaded with CPU-only")
        } catch {
            print("❌ Failed to load Stable Diffusion pipeline:", error)
            pipeline = nil
            throw error
        }
    }
    
    // MARK: - Find Model Resources
    
    private func findModelResources() -> URL? {
        // Try multiple possible locations for the models
        let possiblePaths = [
            "Models",  // Models folder at bundle root
            "closet/Models",  // Models folder in closet directory
            Bundle.main.resourceURL?.appendingPathComponent("Models"),  // Explicit Models path
        ] as [Any]
        
        // Also check if models are directly in resourceURL
        if let resourceURL = Bundle.main.resourceURL {
            // Check if required files exist at root
            let requiredFiles = ["TextEncoder.mlmodelc", "Unet.mlmodelc", "VAEDecoder.mlmodelc", "VAEEncoder.mlmodelc", "vocab.json", "merges.txt"]
            let allExist = requiredFiles.allSatisfy { fileName in
                let fileURL = resourceURL.appendingPathComponent(fileName)
                return FileManager.default.fileExists(atPath: fileURL.path)
            }
            
            if allExist {
                print("✅ Found models at bundle root: \(resourceURL.path)")
                return resourceURL
            }
        }
        
        // Try the possible paths
        for path in possiblePaths {
            var url: URL?
            if let pathString = path as? String {
                if let bundleURL = Bundle.main.resourceURL {
                    url = bundleURL.appendingPathComponent(pathString)
                } else if let bundlePath = Bundle.main.path(forResource: pathString, ofType: nil) {
                    url = URL(fileURLWithPath: bundlePath)
                }
            } else if let pathURL = path as? URL {
                url = pathURL
            }
            
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                // Verify required files exist
                let requiredFiles = ["TextEncoder.mlmodelc", "Unet.mlmodelc", "VAEDecoder.mlmodelc", "VAEEncoder.mlmodelc", "vocab.json", "merges.txt"]
                let allExist = requiredFiles.allSatisfy { fileName in
                    let fileURL = url.appendingPathComponent(fileName)
                    return FileManager.default.fileExists(atPath: fileURL.path)
                }
                
                if allExist {
                    print("✅ Found models at: \(url.path)")
                    return url
                }
            }
        }
        
        // Last resort: try to find Models folder by searching
        if let resourceURL = Bundle.main.resourceURL {
            let modelsURL = resourceURL.appendingPathComponent("Models")
            if FileManager.default.fileExists(atPath: modelsURL.path) {
                print("✅ Found Models folder at: \(modelsURL.path)")
                return modelsURL
            }
        }
        
        print("❌ Could not find model resources. Searched:")
        print("   - Bundle.main.resourceURL")
        for path in possiblePaths {
            print("   - \(path)")
        }
        
        return nil
    }

    // MARK: - Generate Image

    func generate(prompt: String, negativePrompt: String = "") async {
        // Clear previous image to free memory
        generatedImage = nil
        generationProgress = 0.0
        
        // Load pipeline if not already loaded
        if pipeline == nil {
            do {
                try await loadPipeline()
            } catch {
                print("❌ Failed to load pipeline: \(error.localizedDescription)")
                return
            }
        }
        
        guard let pipeline else {
            print("❌ Pipeline not initialized")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Create configuration following the sample code pattern
            var pipelineConfig = StableDiffusionPipeline.Configuration(prompt: prompt)
            
            // Set configuration properties as shown in sample
            pipelineConfig.negativePrompt = negativePrompt
            pipelineConfig.imageCount = 1 // Generate one image at a time to save memory
            pipelineConfig.stepCount = 20 // Reduced from default 50 to save memory and time
            pipelineConfig.seed = UInt32.random(in: 0...UInt32.max)
            pipelineConfig.guidanceScale = 7.5
            pipelineConfig.controlNetInputs = [] // No ControlNet inputs
            
            // Enable use of denoised intermediates for better memory management
            pipelineConfig.useDenoisedIntermediates = true
            
            // Scale factors for SD 2.1 base model (0.18215 is standard)
            // For SD XL, this would be 0.13025
            pipelineConfig.encoderScaleFactor = 0.18215
            pipelineConfig.decoderScaleFactor = 0.18215

            // Generate images with progress tracking
            let images = try pipeline.generateImages(
                configuration: pipelineConfig,
                progressHandler: { [weak self] progress in
                    guard let self = self else { return false }
                    
                    // Update progress on main actor with safe division
                    Task { @MainActor in
                        if progress.stepCount > 0 {
                            self.generationProgress = Double(progress.step) / Double(progress.stepCount)
                        } else {
                            self.generationProgress = 0.0
                        }
                    }
                    
                    print("Generation progress: \(progress.step)/\(progress.stepCount)")
                    return true
                }
            )

            // Process the first generated image
            if let firstImage = images.first, let cgImage = firstImage {
                let image = UIImage(cgImage: cgImage)
                
                // Validate image size before processing
                guard image.size.width > 0 && image.size.height > 0,
                      !image.size.width.isNaN && !image.size.height.isNaN,
                      !image.size.width.isInfinite && !image.size.height.isInfinite else {
                    print("⚠️ Invalid image size: \(image.size)")
                    return
                }
                
                // Downscale image if it's too large to save memory
                // Most SD models generate 512x512, but check and downscale if larger
                let maxDimension: CGFloat = 512
                if image.size.width > maxDimension || image.size.height > maxDimension {
                    if let resized = image.resized(to: maxDimension) {
                        generatedImage = resized
                        print("📐 Image downscaled from \(image.size.width)x\(image.size.height) to max \(maxDimension)")
                    } else {
                        print("⚠️ Failed to resize image, using original")
                        generatedImage = image
                    }
                } else {
                    generatedImage = image
                }
                
                generationProgress = 1.0
            } else {
                print("⚠️ Generated image failed safety check or was nil")
            }
        } catch {
            print("❌ Image generation failed:", error)
            generationProgress = 0.0
        }
    }
    
    // MARK: - Generate Image (Returns UIImage for testing)
    
    func generateImage(prompt: String, negativePrompt: String = "") async throws -> UIImage? {
        // Clear previous image to free memory
        generatedImage = nil
        generationProgress = 0.0
        
        // Load pipeline if not already loaded
        if pipeline == nil {
            try await loadPipeline()
        }
        
        guard let pipeline else {
            throw NSError(domain: "StableDiffusionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Pipeline not initialized"])
        }

        isLoading = true
        defer { isLoading = false }

        // Create configuration following the sample code pattern
        var pipelineConfig = StableDiffusionPipeline.Configuration(prompt: prompt)
        
        // Set configuration properties as shown in sample
        pipelineConfig.negativePrompt = negativePrompt
        pipelineConfig.imageCount = 1 // Generate one image at a time to save memory
        pipelineConfig.stepCount = 20 // Reduced from default 50 to save memory and time
        pipelineConfig.seed = UInt32.random(in: 0...UInt32.max)
        pipelineConfig.guidanceScale = 7.5
        pipelineConfig.controlNetInputs = [] // No ControlNet inputs
        
        // Enable use of denoised intermediates for better memory management
        pipelineConfig.useDenoisedIntermediates = true
        
        // Scale factors for SD 2.1 base model (0.18215 is standard)
        // For SD XL, this would be 0.13025
        pipelineConfig.encoderScaleFactor = 0.18215
        pipelineConfig.decoderScaleFactor = 0.18215

        // Generate images with progress tracking
        let images = try pipeline.generateImages(
            configuration: pipelineConfig,
            progressHandler: { [weak self] progress in
                guard let self = self else { return false }
                
                // Update progress on main actor with safe division
                Task { @MainActor in
                    if progress.stepCount > 0 {
                        self.generationProgress = Double(progress.step) / Double(progress.stepCount)
                    } else {
                        self.generationProgress = 0.0
                    }
                }
                
                print("Generation progress: \(progress.step)/\(progress.stepCount)")
                return true
            }
        )

        // Process the first generated image
        if let firstImage = images.first, let cgImage = firstImage {
            let image = UIImage(cgImage: cgImage)
            
            // Validate image size before processing
            guard image.size.width > 0 && image.size.height > 0,
                  !image.size.width.isNaN && !image.size.height.isNaN,
                  !image.size.width.isInfinite && !image.size.height.isInfinite else {
                print("⚠️ Invalid image size: \(image.size)")
                return nil
            }
            
            // Downscale image if it's too large to save memory
            // Most SD models generate 512x512, but check and downscale if larger
            let maxDimension: CGFloat = 512
            let finalImage: UIImage
            if image.size.width > maxDimension || image.size.height > maxDimension {
                if let resized = image.resized(to: maxDimension) {
                    finalImage = resized
                    print("📐 Image downscaled from \(image.size.width)x\(image.size.height) to max \(maxDimension)")
                } else {
                    print("⚠️ Failed to resize image, using original")
                    finalImage = image
                }
            } else {
                finalImage = image
            }
            
            // Update the published property
            generatedImage = finalImage
            generationProgress = 1.0
            
            return finalImage
        } else {
            print("⚠️ Generated image failed safety check or was nil")
            return nil
        }
    }
    
    // MARK: - Memory Management
    
    func handleMemoryWarning() async {
        print("⚠️ Memory warning received - unloading pipeline")
        await cleanup()
    }
    
    func cleanup() async {
        // Clear generated image
        generatedImage = nil
        generationProgress = 0.0
        
        // Unload pipeline
        guard pipeline != nil else { return }
        
        isUnloading = true
        pipeline = nil
        isPipelineReady = false
        
        // Give system time to release memory
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        isUnloading = false
        print("🗑️ Pipeline unloaded to free memory")
    }
    
    func unloadPipeline() {
        Task {
            await cleanup()
        }
    }
}

// MARK: - UIImage Extension for Resizing

extension UIImage {
    func resized(to maxDimension: CGFloat) -> UIImage? {
        let size = self.size
        
        // Validate input size
        guard size.width > 0 && size.height > 0,
              !size.width.isNaN && !size.height.isNaN,
              !size.width.isInfinite && !size.height.isInfinite,
              maxDimension > 0,
              !maxDimension.isNaN && !maxDimension.isInfinite else {
            print("⚠️ Invalid size or maxDimension in resized(to:): size=\(size), maxDimension=\(maxDimension)")
            return nil
        }
        
        // Calculate aspect ratio safely
        let aspectRatio = size.width / size.height
        
        // Validate aspect ratio
        guard !aspectRatio.isNaN && !aspectRatio.isInfinite && aspectRatio > 0 else {
            print("⚠️ Invalid aspect ratio: \(aspectRatio)")
            return nil
        }
        
        // Calculate new size
        var newSize: CGSize
        if size.width > size.height {
            let newHeight = maxDimension / aspectRatio
            guard !newHeight.isNaN && !newHeight.isInfinite && newHeight > 0 else {
                print("⚠️ Invalid calculated height: \(newHeight)")
                return nil
            }
            newSize = CGSize(width: maxDimension, height: newHeight)
        } else {
            let newWidth = maxDimension * aspectRatio
            guard !newWidth.isNaN && !newWidth.isInfinite && newWidth > 0 else {
                print("⚠️ Invalid calculated width: \(newWidth)")
                return nil
            }
            newSize = CGSize(width: newWidth, height: maxDimension)
        }
        
        // Final validation of newSize before passing to CoreGraphics
        guard newSize.width > 0 && newSize.height > 0,
              !newSize.width.isNaN && !newSize.height.isNaN,
              !newSize.width.isInfinite && !newSize.height.isInfinite else {
            print("⚠️ Invalid newSize calculated: \(newSize)")
            return nil
        }
        
        // Use UIGraphicsImageRenderer for better memory efficiency on iOS
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
