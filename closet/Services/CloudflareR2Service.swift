//
//  CloudflareR2Service.swift
//  closet
//
//  Created by Dan Warner on 2/14/25.
//

import Foundation

/// Service for uploading photos to Cloudflare R2 via Worker
/// Uses Supabase for authentication (JWT tokens)
@MainActor
class CloudflareR2Service {
    static let shared = CloudflareR2Service()
    
    private let supabaseService: SupabaseService
    
    private init() {
        self.supabaseService = SupabaseService.shared
        
        // Validate configuration
        do {
            try CloudflareR2Config.validate()
        } catch {
            print("⚠️ Cloudflare R2 configuration error: \(error.localizedDescription)")
        }
    }
    
    /// Uploads a photo to Cloudflare R2 via Worker and returns the public URL
    /// - Parameters:
    ///   - imageData: The image data to upload (should be compressed JPEG)
    ///   - itemId: The ID of the item this photo belongs to
    ///   - photoId: The ID of the photo
    ///   - userId: The ID of the user (will be validated against Supabase session)
    /// - Returns: The public URL of the uploaded photo
    func uploadPhoto(imageData: Data, itemId: UUID, photoId: UUID, userId: UUID) async throws -> String {
        // Get Supabase JWT token for authentication
        guard let session = supabaseService.currentSession else {
            throw R2Error.notAuthenticated
        }
        
        // CRITICAL: Always use the Supabase user ID from the session
        guard let supabaseUserId = supabaseService.currentUser?.id else {
            throw R2Error.notAuthenticated
        }
        
        // Use Supabase user ID (the source of truth)
        let actualUserId = supabaseUserId
        
        // Create file path: userId/itemId/photoId.jpg
        let fileName = "\(actualUserId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData
        
        print("📤 Uploading photo to R2 via Worker: \(fileName)")
        print("   Using Supabase User ID: \(actualUserId.uuidString)")
        print("   Worker URL: \(CloudflareR2Config.workerURL)")
        print("   Full URL: \(url.absoluteString)")
        print("   Image size: \(imageData.count) bytes")
        print("   Auth token (first 20 chars): \(String(session.accessToken.prefix(20)))...")
        
        // Upload to Worker (which proxies to R2)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw R2Error.invalidResponse
        }
        
        print("   Response status code: \(httpResponse.statusCode)")
        
        // ✅ ALWAYS log response body for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("   Response body: \(responseString)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to parse error message
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                print("❌ R2 upload failed: \(errorMessage)")
                throw R2Error.uploadFailed(errorMessage)
            }
            
            // If no JSON error, return full response
            if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
                print("❌ R2 upload failed with non-JSON response: \(responseString)")
                throw R2Error.uploadFailed(responseString)
            }
            
            let statusMessage = "HTTP \(httpResponse.statusCode)"
            print("❌ R2 upload failed: \(statusMessage)")
            throw R2Error.uploadFailed(statusMessage)
        }
        
        // Parse response to get URL
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let photoURL = json["url"] as? String {
            print("✅ Photo uploaded successfully: \(photoURL)")
            return photoURL
        }
        
        // Fallback: construct URL from custom domain (CDN URL for free caching)
        let photoURL = "\(CloudflareR2Config.customDomain)/\(fileName)"
        print("✅ Photo uploaded successfully: \(photoURL)")
        return photoURL
    }
    
    /// Deletes a photo from Cloudflare R2 via Worker
    /// - Parameters:
    ///   - itemId: The ID of the item this photo belongs to
    ///   - photoId: The ID of the photo
    ///   - userId: The ID of the user (will be validated against Supabase session)
    func deletePhoto(itemId: UUID, photoId: UUID, userId: UUID) async throws {
        // Get Supabase JWT token for authentication
        guard let session = supabaseService.currentSession else {
            throw R2Error.notAuthenticated
        }
        
        // CRITICAL: Always use the Supabase user ID from the session
        guard let supabaseUserId = supabaseService.currentUser?.id else {
            throw R2Error.notAuthenticated
        }
        
        // Use the Supabase user ID to ensure it matches the JWT token
        let actualUserId = (userId == supabaseUserId) ? userId : supabaseUserId
        let fileName = "\(actualUserId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        
        print("🗑️ Deleting photo from R2 via Worker: \(fileName)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw R2Error.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                print("❌ R2 delete failed: \(errorMessage)")
                throw R2Error.deleteFailed(errorMessage)
            }
            let statusMessage = "HTTP \(httpResponse.statusCode)"
            print("❌ R2 delete failed: \(statusMessage)")
            throw R2Error.deleteFailed(statusMessage)
        }
        
        print("✅ Photo deleted successfully: \(fileName)")
    }
    
    /// Uploads a thumbnail to Cloudflare R2 via Worker and returns the public URL
    /// - Parameters:
    ///   - imageData: The thumbnail image data to upload (should be compressed JPEG)
    ///   - itemId: The ID of the item this photo belongs to
    ///   - photoId: The ID of the photo
    ///   - userId: The ID of the user (will be validated against Supabase session)
    /// - Returns: The public URL of the uploaded thumbnail
    func uploadThumbnail(imageData: Data, itemId: UUID, photoId: UUID, userId: UUID) async throws -> String {
        // Get Supabase JWT token for authentication
        guard let session = supabaseService.currentSession else {
            throw R2Error.notAuthenticated
        }
        
        // CRITICAL: Always use the Supabase user ID from the session
        guard let supabaseUserId = supabaseService.currentUser?.id else {
            throw R2Error.notAuthenticated
        }
        
        // Use Supabase user ID (the source of truth)
        let actualUserId = supabaseUserId
        
        // Create file path with _thumb suffix: userId/itemId/photoId_thumb.jpg
        let fileName = "\(actualUserId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString)_thumb.jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData
        
        print("📤 Uploading thumbnail to R2 via Worker: \(fileName)")
        print("   Using Supabase User ID: \(actualUserId.uuidString)")
        print("   Thumbnail size: \(imageData.count) bytes")
        
        // Upload to Worker (which proxies to R2)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw R2Error.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to parse error message
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                print("❌ R2 thumbnail upload failed: \(errorMessage)")
                throw R2Error.uploadFailed(errorMessage)
            }
            
            // If no JSON error, return full response
            if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
                print("❌ R2 thumbnail upload failed with non-JSON response: \(responseString)")
                throw R2Error.uploadFailed(responseString)
            }
            
            let statusMessage = "HTTP \(httpResponse.statusCode)"
            print("❌ R2 thumbnail upload failed: \(statusMessage)")
            throw R2Error.uploadFailed(statusMessage)
        }
        
        // Parse response to get URL
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let thumbnailURL = json["url"] as? String {
            print("✅ Thumbnail uploaded successfully: \(thumbnailURL)")
            return thumbnailURL
        }
        
        // Fallback: construct URL from custom domain (CDN URL for free caching)
        let thumbnailURL = "\(CloudflareR2Config.customDomain)/\(fileName)"
        print("✅ Thumbnail uploaded successfully: \(thumbnailURL)")
        return thumbnailURL
    }
    
    /// Uploads an outfit collage image to Cloudflare R2 via Worker
    /// Path format: userId/outfits/outfitId.jpg
    func uploadOutfitImage(imageData: Data, outfitId: UUID, userId: UUID) async throws -> String {
        guard let session = supabaseService.currentSession else {
            throw R2Error.notAuthenticated
        }
        guard let supabaseUserId = supabaseService.currentUser?.id else {
            throw R2Error.notAuthenticated
        }

        let fileName = "\(supabaseUserId.uuidString)/outfits/\(outfitId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData

        print("📤 Uploading outfit image to R2: \(fileName)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw R2Error.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw R2Error.uploadFailed(errorMessage)
            }
            throw R2Error.uploadFailed("HTTP \(httpResponse.statusCode)")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let imageURL = json["url"] as? String {
            print("✅ Outfit image uploaded: \(imageURL)")
            return imageURL
        }

        let imageURL = "\(CloudflareR2Config.customDomain)/\(fileName)"
        print("✅ Outfit image uploaded: \(imageURL)")
        return imageURL
    }

    /// Deletes an outfit collage image from Cloudflare R2 via Worker
    func deleteOutfitImage(outfitId: UUID, userId: UUID) async throws {
        guard let session = supabaseService.currentSession else {
            throw R2Error.notAuthenticated
        }
        guard let supabaseUserId = supabaseService.currentUser?.id else {
            throw R2Error.notAuthenticated
        }

        let fileName = "\(supabaseUserId.uuidString)/outfits/\(outfitId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        print("🗑️ Deleting outfit image from R2: \(fileName)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw R2Error.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw R2Error.deleteFailed(errorMessage)
            }
            throw R2Error.deleteFailed("HTTP \(httpResponse.statusCode)")
        }

        print("✅ Outfit image deleted from R2: \(fileName)")
    }

    /// Path format: userId/outfits/outfitId_worn.jpg
    func uploadOutfitWornImage(imageData: Data, outfitId: UUID, userId: UUID) async throws -> String {
        guard let session = supabaseService.currentSession else {
            throw R2Error.notAuthenticated
        }
        guard let supabaseUserId = supabaseService.currentUser?.id else {
            throw R2Error.notAuthenticated
        }

        let fileName = "\(supabaseUserId.uuidString)/outfits/\(outfitId.uuidString)_worn.jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData

        print("📤 Uploading outfit worn image to R2: \(fileName)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw R2Error.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw R2Error.uploadFailed(errorMessage)
            }
            throw R2Error.uploadFailed("HTTP \(httpResponse.statusCode)")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let imageURL = json["url"] as? String {
            print("✅ Outfit worn image uploaded: \(imageURL)")
            return imageURL
        }

        let imageURL = "\(CloudflareR2Config.customDomain)/\(fileName)"
        print("✅ Outfit worn image uploaded: \(imageURL)")
        return imageURL
    }

    func deleteOutfitWornImage(outfitId: UUID, userId: UUID) async throws {
        guard let session = supabaseService.currentSession else {
            throw R2Error.notAuthenticated
        }
        guard let supabaseUserId = supabaseService.currentUser?.id else {
            throw R2Error.notAuthenticated
        }

        let fileName = "\(supabaseUserId.uuidString)/outfits/\(outfitId.uuidString)_worn.jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        print("🗑️ Deleting outfit worn image from R2: \(fileName)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw R2Error.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw R2Error.deleteFailed(errorMessage)
            }
            throw R2Error.deleteFailed("HTTP \(httpResponse.statusCode)")
        }

        print("✅ Outfit worn image deleted from R2: \(fileName)")
    }

    /// Gets the public URL for a photo (for display)
    /// - Parameters:
    ///   - itemId: The ID of the item this photo belongs to
    ///   - photoId: The ID of the photo
    ///   - userId: The ID of the user
    /// - Returns: The public URL of the photo (CDN URL for free caching)
    func getPublicURL(itemId: UUID, photoId: UUID, userId: UUID) -> String {
        let fileName = "\(userId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString).jpg"
        return "\(CloudflareR2Config.customDomain)/\(fileName)"
    }
    
    /// Gets the public URL for a thumbnail (for display)
    /// - Parameters:
    ///   - itemId: The ID of the item this photo belongs to
    ///   - photoId: The ID of the photo
    ///   - userId: The ID of the user
    /// - Returns: The public URL of the thumbnail (CDN URL for free caching)
    func getThumbnailURL(itemId: UUID, photoId: UUID, userId: UUID) -> String {
        let fileName = "\(userId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString)_thumb.jpg"
        return "\(CloudflareR2Config.customDomain)/\(fileName)"
    }
}

// MARK: - R2 Errors

enum R2Error: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case uploadFailed(String)
    case deleteFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .invalidResponse:
            return "Invalid response from server"
        case .uploadFailed(let message):
            return "Failed to upload photo: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete photo: \(message)"
        }
    }
}

