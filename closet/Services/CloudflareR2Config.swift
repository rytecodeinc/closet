//
//  CloudflareR2Config.swift
//  closet
//
//  Created by Dan Warner on 2/14/25.
//

import Foundation

/// Configuration for Cloudflare R2 storage via Worker
struct CloudflareR2Config {
    /// Your Cloudflare Worker URL
    /// Note: No trailing slash - paths will be appended
    static let workerURL = "https://redress-item-photos-api.rytecode.workers.dev"
    
    /// Custom domain for CDN access (enables free caching)
    /// Note: No trailing slash - paths will be appended
    static let customDomain = "https://images.redress.me"
    
    // MARK: - Validation
    
    /// Validates the configuration
    static func validate() throws {
        guard let url = URL(string: workerURL), url.scheme == "https" else {
            throw R2ConfigError.invalidURL
        }
    }
    
    /// Checks if the configuration is valid
    static var isConfigured: Bool {
        do {
            try validate()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Configuration Errors

enum R2ConfigError: LocalizedError {
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Cloudflare Worker URL. Must be a valid HTTPS URL."
        }
    }
}

