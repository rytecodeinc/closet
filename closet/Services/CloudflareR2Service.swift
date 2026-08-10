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

    /// Fresh JWT + Supabase user id for Worker auth. Never use cached `currentSession` alone —
    /// it can hold an expired access token while the Auth client still has a valid refresh token.
    private func authenticatedUploadContext() async throws -> (accessToken: String, userId: UUID) {
        do {
            let session = try await supabaseService.freshSession()
            return (session.accessToken, session.user.id)
        } catch {
            throw R2Error.notAuthenticated
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
        let (accessToken, actualUserId) = try await authenticatedUploadContext()
        
        // Create file path: userId/itemId/photoId.jpg
        let fileName = "\(actualUserId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData
        
        print("📤 Uploading photo to R2 via Worker: \(fileName)")
        print("   Using Supabase User ID: \(actualUserId.uuidString)")
        print("   Worker URL: \(CloudflareR2Config.workerURL)")
        print("   Full URL: \(url.absoluteString)")
        print("   Image size: \(imageData.count) bytes")
        print("   Auth token (first 20 chars): \(String(accessToken.prefix(20)))...")
        
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
        let (accessToken, supabaseUserId) = try await authenticatedUploadContext()
        
        // Use the Supabase user ID to ensure it matches the JWT token
        let actualUserId = (userId == supabaseUserId) ? userId : supabaseUserId
        let fileName = "\(actualUserId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
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
        let (accessToken, actualUserId) = try await authenticatedUploadContext()
        
        // Create file path with _thumb suffix: userId/itemId/photoId_thumb.jpg
        let fileName = "\(actualUserId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString)_thumb.jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
        let (accessToken, supabaseUserId) = try await authenticatedUploadContext()

        let fileName = "\(supabaseUserId.uuidString)/outfits/\(outfitId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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

    /// Deletes a Redress suggestion collage from R2.
    /// Path format: `ownerUserId/outfit-suggestions/suggestionId.jpg` (suggester's prefix).
    func deleteOutfitSuggestionImage(suggestionId: UUID, ownerUserId: UUID) async throws {
        let (accessToken, _) = try await authenticatedUploadContext()

        let fileName = "\(ownerUserId.uuidString)/outfit-suggestions/\(suggestionId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("🗑️ Deleting outfit suggestion image from R2: \(fileName)")

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

        print("✅ Outfit suggestion image deleted from R2: \(fileName)")
    }

    /// Uploads a Redress outfit suggestion collage to R2.
    /// Path format: userId/outfit-suggestions/suggestionId.jpg
    func uploadOutfitSuggestionImage(imageData: Data, suggestionId: UUID, userId: UUID) async throws -> String {
        let (accessToken, supabaseUserId) = try await authenticatedUploadContext()

        let fileName = "\(supabaseUserId.uuidString)/outfit-suggestions/\(suggestionId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData

        print("📤 Uploading outfit suggestion image to R2: \(fileName)")

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
            print("✅ Outfit suggestion image uploaded: \(imageURL)")
            return imageURL
        }

        let imageURL = "\(CloudflareR2Config.customDomain)/\(fileName)"
        print("✅ Outfit suggestion image uploaded: \(imageURL)")
        return imageURL
    }

    /// Deletes an outfit collage image from Cloudflare R2 via Worker
    func deleteOutfitImage(outfitId: UUID, userId: UUID) async throws {
        let (accessToken, supabaseUserId) = try await authenticatedUploadContext()

        let fileName = "\(supabaseUserId.uuidString)/outfits/\(outfitId.uuidString).jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

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
        let (accessToken, supabaseUserId) = try await authenticatedUploadContext()

        let fileName = "\(supabaseUserId.uuidString)/outfits/\(outfitId.uuidString)_worn.jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
        let (_, supabaseUserId) = try await authenticatedUploadContext()

        // R2 keys are case-sensitive; historical uploads may use either UUID casing.
        let candidates = [
            "\(supabaseUserId.uuidString)/outfits/\(outfitId.uuidString)_worn.jpg",
            "\(supabaseUserId.uuidString.lowercased())/outfits/\(outfitId.uuidString.lowercased())_worn.jpg",
        ]
        var uniquePaths = [String]()
        for path in candidates where !uniquePaths.contains(path) {
            uniquePaths.append(path)
        }

        var lastError: Error?
        var deletedAny = false
        for fileName in uniquePaths {
            do {
                try await deleteWorkerObject(atPath: fileName)
                deletedAny = true
            } catch {
                lastError = error
                print("⚠️ Outfit worn R2 delete attempt failed for \(fileName): \(error.localizedDescription)")
            }
        }

        if !deletedAny, let lastError {
            throw lastError
        }
    }

    /// Deletes an R2 object using a stored public/worker URL (path after host).
    func deleteObject(atStoredURL urlString: String) async throws {
        guard let path = Self.workerObjectPath(fromStoredURL: urlString), !path.isEmpty else {
            print("⚠️ Could not derive R2 path from URL: \(urlString)")
            return
        }
        try await deleteWorkerObject(atPath: path)
        let lowered = path.lowercased()
        if lowered != path {
            try? await deleteWorkerObject(atPath: lowered)
        }
    }

    nonisolated static func workerObjectPath(fromStoredURL urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed) else {
            // Already a bare object key
            return trimmed.split(separator: "?").first.map(String.init)
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? nil : path
    }

    private func deleteWorkerObject(atPath fileName: String) async throws {
        let (accessToken, _) = try await authenticatedUploadContext()
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("🗑️ Deleting R2 object via Worker: \(fileName)")

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

        print("✅ R2 object deleted: \(fileName)")
    }

    /// Profile avatar uses exactly **one** object per user: `userId/profile/avatar.jpg`.
    /// Each PUT replaces that object. The returned public URL includes a `v` query param so
    /// CDN / URLSession caches treat each upload as a new resource (same path, new cache key).
    func uploadProfileAvatar(imageData: Data, userId _: UUID) async throws -> String {
        let (accessToken, supabaseUserId) = try await authenticatedUploadContext()

        let fileName = "\(supabaseUserId.uuidString)/profile/avatar.jpg"
        let workerPutURL = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!
        let version = Int(Date().timeIntervalSince1970 * 1000)
        let canonicalPublicURL = "\(CloudflareR2Config.customDomain)/\(fileName)?v=\(version)"

        var request = URLRequest(url: workerPutURL)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData

        print("📤 Uploading profile avatar to R2 (replaces existing): \(fileName)")

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

        // Drop any cached responses for this avatar path (with or without prior ?v=).
        Self.removeCachedResponses(forAvatarPath: fileName)

        print("✅ Profile avatar replaced in R2: \(canonicalPublicURL)")
        return canonicalPublicURL
    }

    func deleteProfileAvatar(userId _: UUID) async throws {
        let (accessToken, supabaseUserId) = try await authenticatedUploadContext()

        let fileName = "\(supabaseUserId.uuidString)/profile/avatar.jpg"
        let url = URL(string: "\(CloudflareR2Config.workerURL)/\(fileName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("🗑️ Deleting profile avatar from R2: \(fileName)")

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

        Self.removeCachedResponses(forAvatarPath: fileName)
        print("✅ Profile avatar deleted from R2: \(fileName)")
    }

    /// Removes URLCache entries for the avatar object (bare CDN URL).
    private static func removeCachedResponses(forAvatarPath fileName: String) {
        let bare = "\(CloudflareR2Config.customDomain)/\(fileName)"
        guard let bareURL = URL(string: bare) else { return }
        URLCache.shared.removeCachedResponse(for: URLRequest(url: bareURL))
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

