//
//  VisionAnalysisService.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import Vision
import UIKit
import CoreImage
import CoreML

/// Result from Vision analysis
struct VisionAnalysisResult {
    var suggestedCategory: String?
    var confidence: Float = 0.0
    var allClassifications: [(identifier: String, confidence: Float)] = []
}

/// Service for analyzing images using Apple Vision framework with FastViT Core ML model
class VisionAnalysisService {
    static let shared = VisionAnalysisService()
    
    private init() {}
    
    // MARK: - Core ML Model
    
    /// Lazy-loaded FastViT T8 Core ML model for image classification
    private lazy var fastViTModel: VNCoreMLModel? = {
        guard let modelURL = Bundle.main.url(forResource: "FastViTT8F16", withExtension: "mlpackage") else {
            print("⚠️ FastViT model not found. Falling back to built-in VNClassifyImageRequest.")
            return nil
        }
        
        do {
            let model = try MLModel(contentsOf: modelURL)
            return try VNCoreMLModel(for: model)
        } catch {
            print("⚠️ Failed to load FastViT model: \(error.localizedDescription). Falling back to built-in VNClassifyImageRequest.")
            return nil
        }
    }()
    
    // MARK: - Category Mapping
    
    /// Maps Vision classification identifiers to app category names
    /// Uses comprehensive mapping based on common clothing item classifications
    private let categoryMapping: [String: String] = [
        // Tops
        "shirt": "Tops",
        "t-shirt": "Tops",
        "tshirt": "Tops",
        "blouse": "Tops",
        "sweater": "Tops",
        "pullover": "Tops",
        "hoodie": "Tops",
        "tank top": "Tops",
        "tank": "Tops",
        "top": "Tops",
        "polo shirt": "Tops",
        "cardigan": "Tops",
        "jersey": "Tops",
        
        // Bottoms
        "pants": "Bottoms",
        "trousers": "Bottoms",
        "jeans": "Bottoms",
        "shorts": "Bottoms",
        "skirt": "Bottoms",
        "leggings": "Bottoms",
        "tights": "Bottoms",
        
        // Outerwear
        "jacket": "Outerwear",
        "coat": "Outerwear",
        "blazer": "Outerwear",
        "parka": "Outerwear",
        "windbreaker": "Outerwear",
        "raincoat": "Outerwear",
        "overcoat": "Outerwear",
        
        // Dresses
        "dress": "Dresses",
        "gown": "Dresses",
        "frock": "Dresses",
        
        // Shoes
        "shoe": "Shoes",
        "sneaker": "Shoes",
        "boot": "Shoes",
        "sandal": "Shoes",
        "high heel": "Shoes",
        "heel": "Shoes",
        "flat": "Shoes",
        "loafer": "Shoes",
        "oxford": "Shoes",
        "pump": "Shoes",
        
        // Accessories
        "bag": "Accessories",
        "handbag": "Accessories",
        "purse": "Accessories",
        "backpack": "Accessories",
        "hat": "Accessories",
        "cap": "Accessories",
        "belt": "Accessories",
        "scarf": "Accessories",
        "gloves": "Accessories",
        "watch": "Accessories",
        "jewelry": "Accessories",
        "necklace": "Accessories",
        "bracelet": "Accessories",
        
        // Swimwear
        "swimsuit": "Swimwear",
        "bikini": "Swimwear",
        "swimwear": "Swimwear",
        "bathing suit": "Swimwear",
        
        // Activewear
        "athletic": "Activewear",
        "sportswear": "Activewear",
        "activewear": "Activewear",
        "gym": "Activewear",
        "yoga": "Activewear",
        "running": "Activewear",
        
        // Suits
        "suit": "Suits",
        "business suit": "Suits"
    ]
    
    /// Valid app category names (for normalization)
    private let validCategories: Set<String> = [
        "Tops", "Bottoms", "Outerwear", "Shoes", "Accessories",
        "Dresses", "Suits", "Swimwear", "Activewear"
    ]
    
    // MARK: - Configuration
    
    /// Minimum confidence threshold for category suggestions
    /// Best practice: Use 0.3-0.5 for initial suggestions, allow user to override
    private let minimumConfidence: Float = 0.3
    
    /// Number of top classifications to check
    private let topClassificationsCount = 15
    
    // MARK: - Public API
    
    /// Analyzes an image and suggests a category using FastViT T8 Core ML model
    /// Falls back to built-in VNClassifyImageRequest if model is not available
    /// - Parameter image: The image to analyze
    /// - Returns: VisionAnalysisResult with suggested category and confidence
    func analyzeCategory(from image: UIImage) async throws -> VisionAnalysisResult {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImage
        }
        
        // Try FastViT model first, fall back to built-in classifier if unavailable
        if let coreMLModel = fastViTModel {
            return try await analyzeWithFastViT(cgImage: cgImage)
        } else {
            return try await analyzeWithBuiltInClassifier(cgImage: cgImage)
        }
    }
    
    /// Analyzes image using FastViT T8 Core ML model
    private func analyzeWithFastViT(cgImage: CGImage) async throws -> VisionAnalysisResult {
        guard let model = fastViTModel else {
            throw VisionError.analysisFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                guard let self = self else {
                    continuation.resume(throwing: VisionError.analysisFailed)
                    return
                }
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: VisionAnalysisResult())
                    return
                }
                
                // Process classifications
                let result = self.processClassifications(observations)
                continuation.resume(returning: result)
            }
            
            // Center crop and scale for optimal FastViT performance
            request.imageCropAndScaleOption = .centerCrop
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Analyzes image using built-in VNClassifyImageRequest (fallback)
    private func analyzeWithBuiltInClassifier(cgImage: CGImage) async throws -> VisionAnalysisResult {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { [weak self] request, error in
                guard let self = self else {
                    continuation.resume(throwing: VisionError.analysisFailed)
                    return
                }
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: VisionAnalysisResult())
                    return
                }
                
                // Process classifications
                let result = self.processClassifications(observations)
                continuation.resume(returning: result)
            }
            
            // Use revision 1 for better accuracy (iOS 15+)
            if #available(iOS 15.0, *) {
                request.revision = VNClassifyImageRequestRevision1
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Normalizes a category name from URL metadata to match app categories
    /// - Parameter categoryName: Category name from URL metadata
    /// - Returns: Normalized category name that matches app categories, or nil
    func normalizeCategoryFromURL(_ categoryName: String?) -> String? {
        guard let categoryName = categoryName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !categoryName.isEmpty else {
            return nil
        }
        
        let normalized = categoryName.capitalized
        let lowercased = normalized.lowercased()
        
        // Direct match
        if validCategories.contains(normalized) {
            return normalized
        }
        
        // Case-insensitive match
        if let match = validCategories.first(where: { $0.lowercased() == lowercased }) {
            return match
        }
        
        // Handle plural forms (e.g., "Dresses" -> "Dresses" which is valid, but also handle singular)
        let singularMapping: [String: String] = [
            "dress": "Dresses",
            "top": "Tops",
            "bottom": "Bottoms",
            "shoe": "Shoes",
            "accessory": "Accessories",
            "suit": "Suits"
        ]
        
        // Check singular form
        if let singularMatch = singularMapping[lowercased] {
            return singularMatch
        }
        
        // Check if it's a plural form we recognize
        for (singular, plural) in singularMapping {
            if lowercased == plural.lowercased() || lowercased == "\(singular)s" {
                return plural
            }
        }
        
        // Fuzzy matching - check if URL category contains or is contained by app categories
        for appCategory in validCategories {
            let appCategoryLower = appCategory.lowercased()
            // Check if URL category contains app category name or vice versa
            if lowercased.contains(appCategoryLower) || appCategoryLower.contains(lowercased) {
                return appCategory
            }
        }
        
        // Map common URL category variations
        let urlCategoryMapping: [String: String] = [
            "clothing": "Tops", // Generic fallback
            "apparel": "Tops",
            "women's": "Tops",
            "men's": "Tops",
            "women": "Tops",
            "men": "Tops",
            "ladies": "Tops",
            "mens": "Tops",
            "womens": "Tops",
            "upper": "Tops",
            "lower": "Bottoms",
            "footwear": "Shoes",
            "shoes & boots": "Shoes",
            "bags & accessories": "Accessories",
            "accessories & bags": "Accessories",
            "jewelry & watches": "Accessories",
            "swim": "Swimwear",
            "swim & beach": "Swimwear",
            "active": "Activewear",
            "sport": "Activewear",
            "sports": "Activewear",
            "athletic": "Activewear",
            "outer": "Outerwear",
            "jackets & coats": "Outerwear",
            "dress": "Dresses",
            "dresses": "Dresses", // Explicit plural form
            "dresses & jumpsuits": "Dresses",
            "women's clothing": "Tops", // Generic, but prefer more specific if available
            "women's dresses": "Dresses"
        ]
        
        if let mapped = urlCategoryMapping[lowercased] {
            return mapped
        }
        
        return nil
    }
    
    /// Combines URL metadata category and Vision analysis for best accuracy
    /// - Parameters:
    ///   - urlCategory: Category from URL metadata (normalized)
    ///   - visionResult: Result from Vision analysis
    /// - Returns: Best category suggestion with confidence
    func combineCategorySources(urlCategory: String?, visionResult: VisionAnalysisResult) -> (category: String?, confidence: Float, source: String) {
        let normalizedURLCategory = normalizeCategoryFromURL(urlCategory)
        
        // If both sources agree, use that with high confidence
        if let urlCat = normalizedURLCategory,
           let visionCat = visionResult.suggestedCategory,
           urlCat == visionCat {
            return (urlCat, max(0.8, visionResult.confidence), "both")
        }
        
        // If URL category exists and is valid, prefer it (URLs/breadcrumbs are often more accurate)
        // Breadcrumbs are especially reliable as they come from the site's navigation structure
        if let urlCat = normalizedURLCategory {
            // Higher confidence for breadcrumb categories (they're from site structure)
            // Check if it came from breadcrumbs by seeing if it's a specific category
            let isSpecificCategory = !urlCat.lowercased().contains("&") && 
                                     !urlCat.lowercased().contains("clothing, shoes")
            let confidence: Float = isSpecificCategory ? 0.85 : 0.7
            return (urlCat, confidence, "url")
        }
        
        // Fall back to Vision if confidence is good
        if let visionCat = visionResult.suggestedCategory,
           visionResult.confidence >= minimumConfidence {
            return (visionCat, visionResult.confidence, "vision")
        }
        
        // If Vision has a suggestion but low confidence, still return it (user can override)
        if let visionCat = visionResult.suggestedCategory {
            return (visionCat, visionResult.confidence, "vision")
        }
        
        return (nil, 0.0, "none")
    }
    
    // MARK: - Private Helpers
    
    /// Processes Vision classification observations to find matching category
    private func processClassifications(_ observations: [VNClassificationObservation]) -> VisionAnalysisResult {
        var allClassifications: [(identifier: String, confidence: Float)] = []
        var bestCategory: String?
        var bestConfidence: Float = 0.0
        
        // Check top classifications
        let topObservations = observations.prefix(topClassificationsCount)
        
        for observation in topObservations {
            let identifier = observation.identifier.lowercased()
            let confidence = observation.confidence
            
            // Store all classifications for debugging
            allClassifications.append((observation.identifier, confidence))
            
            // Check if this classification maps to any of our categories
            for (key, category) in categoryMapping {
                if identifier.contains(key) && confidence > bestConfidence {
                    bestCategory = category
                    bestConfidence = confidence
                    break
                }
            }
        }
        
        // Only return suggestion if confidence meets threshold
        if let category = bestCategory, bestConfidence >= minimumConfidence {
            return VisionAnalysisResult(
                suggestedCategory: category,
                confidence: bestConfidence,
                allClassifications: allClassifications
            )
        }
        
        // Return result even if below threshold (user can still see it)
        return VisionAnalysisResult(
            suggestedCategory: bestCategory,
            confidence: bestConfidence,
            allClassifications: allClassifications
        )
    }
    
    enum VisionError: Error {
        case invalidImage
        case analysisFailed
    }
}

