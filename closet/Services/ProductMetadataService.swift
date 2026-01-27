//
//  ProductMetadataService.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import UIKit
import SwiftSoup
import WebKit
import ObjectiveC

struct ProductMetadata {
    let title: String?
    let brand: String?
    let category: String?
    let price: Decimal?
    let priceString: String? // Original price string to preserve exact precision (cents)
    let priceCurrency: String?
    let description: String?
    let imageURL: URL?
    let sourceURL: URL
}

class ProductMetadataService {
    static let shared = ProductMetadataService()
    
    private init() {}
    
    func fetchMetadata(from url: URL) async throws -> ProductMetadata {
        // Try URLSession first with proper headers - many sites serve full HTML to crawlers
        // This is faster and more reliable than WKWebView for most sites
        var html: String?
        
        do {
            html = try await fetchHTMLWithURLSession(from: url)
            
            // Check if we got a redirect page (no og:image) - common with app deep links
            if let htmlContent = html, !htmlContent.contains("og:image") && !htmlContent.contains("property=\"og:image\"") {
                html = try await fetchHTMLWithWebView(from: url)
            }
        } catch {
            do {
                html = try await fetchHTMLWithWebView(from: url)
            } catch {
                throw error
            }
        }
        
        guard let html = html else {
            throw MetadataError.invalidHTML
        }
        
        return parseMetadata(from: html, sourceURL: url)
    }
    
    /// Fetches HTML using URLSession with proper crawler headers
    /// This is faster and works for most sites that serve full HTML to crawlers
    private func fetchHTMLWithURLSession(from url: URL) async throws -> String {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10.0
        configuration.timeoutIntervalForResource = 15.0
        
        var request = URLRequest(url: url)
        
        // Set headers to identify as a browser/crawler, not an app
        // Using Googlebot user agent often gets the full page for SEO purposes
        request.setValue("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        
        // Check for redirects
        if let httpResponse = response as? HTTPURLResponse {
            // Handle redirects
            if (300...399).contains(httpResponse.statusCode),
               let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let redirectURL = URL(string: location, relativeTo: url) {
                // Recursively follow redirect (with limit to prevent infinite loops)
                return try await fetchHTMLWithURLSession(from: redirectURL)
            }
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw MetadataError.invalidHTML
        }
        
        return html
    }
    
    /// Fetches HTML content using WKWebView to execute JavaScript and get rendered content
    private func fetchHTMLWithWebView(from url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let extractor = WebViewHTMLExtractor(continuation: continuation)
                extractor.extractHTML(from: url)
            }
        }
    }
    
    private func parseMetadata(from html: String, sourceURL: URL) -> ProductMetadata {
        var title: String?
        var brand: String?
        var category: String?
        var price: Decimal?
        var priceString: String? // Original price string to preserve exact precision
        var priceCurrency: String?
        var description: String?
        var imageURL: URL?
        
        // Parse Open Graph tags
        title = extractOGTag(html: html, property: "og:title") ?? extractMetaTag(html: html, name: "title")
        
        // Extract brand from Open Graph tags, but filter out marketplace names
        let ogBrand = extractOGTag(html: html, property: "og:brand") ?? 
                      extractOGTag(html: html, property: "product:brand") ??
                      extractOGTag(html: html, property: "product:brand:category")
        
        // Filter out marketplace names from Open Graph brand tags
        if let ogBrandValue = ogBrand {
            let marketplaceNames = ["depop", "poshmark", "mercari", "grailed", "vestiaire", "therealreal",
                                     "thredup", "vinted", "tradesy", "rebag", "fashionphile", "amazon",
                                     "target", "walmart", "ebay", "etsy", "shopify", "bigcommerce"]
            let brandLower = ogBrandValue.lowercased()
            if marketplaceNames.contains(where: { brandLower.contains($0) }) {
                brand = nil
            } else {
                brand = ogBrandValue
            }
        } else {
            brand = nil
        }
        // Try breadcrumbs first (most accurate), then fall back to Open Graph
        category = extractCategoryFromBreadcrumbs(html: html, sourceURL: sourceURL) ??
                   extractOGTag(html: html, property: "og:product:category") ?? 
                   extractOGTag(html: html, property: "product:category") ??
                   extractOGTag(html: html, property: "product:type")
        description = extractOGTag(html: html, property: "og:description") ?? extractMetaTag(html: html, name: "description")
        
        // Parse price - try multiple Open Graph price formats
        if let ogPriceString = extractOGTag(html: html, property: "og:price:amount") ?? 
                               extractOGTag(html: html, property: "product:price:amount") {
            // Store original price string to preserve exact precision (cents)
            priceString = ogPriceString
            // Clean price string (remove currency symbols, commas, etc.)
            let cleanedPrice = ogPriceString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            price = Decimal(string: cleanedPrice)
        }
        priceCurrency = extractOGTag(html: html, property: "og:price:currency") ?? 
                        extractOGTag(html: html, property: "product:price:currency")
        
        // Parse image - check og:image first, then fall back to srcset
        // og:image is usually the most reliable product image
        
        // Try og:image first (most reliable for product images)
        var ogImageURLString: String?
        if let secureURL = extractOGTag(html: html, property: "og:image:secure_url") {
            ogImageURLString = secureURL
        } else if let imageURL = extractOGTag(html: html, property: "og:image") {
            ogImageURLString = imageURL
        }
        
        if let imageURLString = ogImageURLString {
            // Try to create URL from og:image
            if let ogURL = URL(string: imageURLString, relativeTo: sourceURL) ?? URL(string: imageURLString) {
                if !isProfileOrAvatarURL(ogURL) {
                    imageURL = ogURL
                }
            }
        }
        
        // If og:image not found or filtered out, try srcset for highest resolution
        if imageURL == nil {
            if let srcsetURL = extractLargestImageFromSrcset(html: html, baseURL: sourceURL) {
                imageURL = srcsetURL
            }
        }
        
        // Try JSON-LD structured data (Schema.org Product)
        if let jsonLD = extractJSONLD(html: html) {
            if title == nil, let jsonTitle = jsonLD["name"] as? String {
                title = jsonTitle
            }
            
            // Extract brand from JSON-LD
            if brand == nil {
                var jsonBrandValue: String?
                if let jsonBrand = jsonLD["brand"] as? [String: Any] {
                    jsonBrandValue = jsonBrand["name"] as? String
                } else if let jsonBrand = jsonLD["brand"] as? String {
                    jsonBrandValue = jsonBrand
                } else if let manufacturer = jsonLD["manufacturer"] as? [String: Any], let manufacturerName = manufacturer["name"] as? String {
                    jsonBrandValue = manufacturerName
                }
                
                // Filter out marketplace names from JSON-LD brand
                if let brandValue = jsonBrandValue {
                    let marketplaceNames = ["depop", "poshmark", "mercari", "grailed", "vestiaire", "therealreal",
                                             "thredup", "vinted", "tradesy", "rebag", "fashionphile", "amazon",
                                             "target", "walmart", "ebay", "etsy", "shopify", "bigcommerce"]
                    let brandLower = brandValue.lowercased()
                    if !marketplaceNames.contains(where: { brandLower.contains($0) }) {
                        brand = brandValue
                    }
                }
            }
            
            // Extract category from JSON-LD
            if category == nil {
                if let jsonCategory = jsonLD["category"] as? String {
                    category = jsonCategory
                } else if let categoryArray = jsonLD["category"] as? [String], let firstCategory = categoryArray.first {
                    category = firstCategory
                } else if let productType = jsonLD["@type"] as? String, productType != "Product" {
                    category = productType
                }
            }
            
            // Extract price from offers
            if price == nil {
                if let offers = jsonLD["offers"] as? [String: Any] {
                    if let jsonPriceString = offers["price"] as? String {
                        // Store original price string to preserve exact precision
                        priceString = jsonPriceString
                        let cleanedPrice = jsonPriceString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
                        price = Decimal(string: cleanedPrice)
                    } else if let priceNum = offers["price"] as? NSNumber {
                        // Format NSNumber to preserve decimal places
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.minimumFractionDigits = 2
                        formatter.maximumFractionDigits = 2
                        formatter.locale = Locale(identifier: "en_US")
                        priceString = formatter.string(from: priceNum)
                        price = Decimal(string: priceNum.stringValue)
                    } else if let priceDouble = offers["price"] as? Double {
                        // Format Double to preserve decimal places
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.minimumFractionDigits = 2
                        formatter.maximumFractionDigits = 2
                        formatter.locale = Locale(identifier: "en_US")
                        priceString = formatter.string(from: NSNumber(value: priceDouble))
                        price = Decimal(priceDouble)
                    }
                    if priceCurrency == nil, let currency = offers["priceCurrency"] as? String {
                        priceCurrency = currency
                    }
                } else if let offersArray = jsonLD["offers"] as? [[String: Any]], let firstOffer = offersArray.first {
                    if let jsonPriceString = firstOffer["price"] as? String {
                        // Store original price string to preserve exact precision
                        priceString = jsonPriceString
                        let cleanedPrice = jsonPriceString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
                        price = Decimal(string: cleanedPrice)
                    } else if let priceNum = firstOffer["price"] as? NSNumber {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.minimumFractionDigits = 2
                        formatter.maximumFractionDigits = 2
                        formatter.locale = Locale(identifier: "en_US")
                        priceString = formatter.string(from: priceNum)
                        price = Decimal(string: priceNum.stringValue)
                    } else if let priceDouble = firstOffer["price"] as? Double {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.minimumFractionDigits = 2
                        formatter.maximumFractionDigits = 2
                        formatter.locale = Locale(identifier: "en_US")
                        priceString = formatter.string(from: NSNumber(value: priceDouble))
                        price = Decimal(priceDouble)
                    }
                    if priceCurrency == nil, let currency = firstOffer["priceCurrency"] as? String {
                        priceCurrency = currency
                    }
                }
            }
            
            // Extract image from JSON-LD (filter profile/avatar URLs)
            if imageURL == nil {
                if let imageString = jsonLD["image"] as? String,
                   let url = URL(string: imageString, relativeTo: sourceURL) ?? URL(string: imageString),
                   !isProfileOrAvatarURL(url) {
                    imageURL = url
                } else if let imageArray = jsonLD["image"] as? [String] {
                    // Try each image in array until we find one that's not a profile/avatar
                    for imageString in imageArray {
                        if let url = URL(string: imageString, relativeTo: sourceURL) ?? URL(string: imageString),
                           !isProfileOrAvatarURL(url) {
                            imageURL = url
                            break
                        }
                    }
                } else if let imageObject = jsonLD["image"] as? [String: Any], let imageUrlString = imageObject["url"] as? String,
                          let url = URL(string: imageUrlString, relativeTo: sourceURL) ?? URL(string: imageUrlString),
                          !isProfileOrAvatarURL(url) {
                    imageURL = url
                }
            }
            
            // Extract description if not already found
            if description == nil, let jsonDescription = jsonLD["description"] as? String {
                description = jsonDescription
            }
        }
        
        // Breadcrumb extraction already done above, but if we didn't find one,
        // try again here as a final check (in case JSON-LD wasn't parsed yet)
        if let existingCategory = category, isGenericCategory(existingCategory) {
            // Category exists but is generic, try to get better one from breadcrumbs
            if let breadcrumbCategory = extractCategoryFromBreadcrumbs(html: html, sourceURL: sourceURL) {
                category = breadcrumbCategory
            }
        } else if category == nil {
            // No category found, try breadcrumbs
            if let breadcrumbCategory = extractCategoryFromBreadcrumbs(html: html, sourceURL: sourceURL) {
                category = breadcrumbCategory
            }
        }
        
        // Extract brand from marketplace-specific sources (e.g., Depop aria-label)
        // IMPORTANT: For marketplace sites, prioritize marketplace-specific extraction
        // This should run even if brand was set from Open Graph/JSON-LD (which might be wrong)
        
        // Check if this is a Depop URL (handles depop.com, depop.app.links, etc.)
        let isDepopURL = {
            guard let host = sourceURL.host else { return false }
            return host.contains("depop.com") || host.contains("depop.app") || host.contains("depop")
        }()
        
        if isDepopURL {
            // For Depop, always try marketplace extraction (it's more reliable than OG/JSON-LD)
            if let marketplaceBrand = extractBrandFromMarketplace(html: html, sourceURL: sourceURL) {
                brand = marketplaceBrand
            }
        } else if brand == nil {
            // For non-marketplace sites, only run if brand is nil
            if let marketplaceBrand = extractBrandFromMarketplace(html: html, sourceURL: sourceURL) {
                brand = marketplaceBrand
            }
        }
        
        // Helper function to check if URL is a marketplace site
        func isMarketplaceSite(host: String?) -> Bool {
            guard let host = host else { return false }
            // Check for Depop variations (depop.com, depop.app.link, etc.)
            if host.contains("depop") {
                return true
            }
            // Check for other marketplaces
            let marketplaceDomains = ["poshmark.com", "mercari.com", "grailed.com", 
                                       "vestiaire.com", "therealreal.com", "thredup.com", "vinted.com",
                                       "tradesy.com", "rebag.com", "fashionphile.com", "amazon.com",
                                       "target.com", "walmart.com", "ebay.com", "etsy.com", "shopify.com"]
            return marketplaceDomains.contains(where: { host.contains($0) })
        }
        
        // Extract brand from site title (better than domain for accuracy)
        // SKIP this for marketplace sites - they are not brands
        if !isMarketplaceSite(host: sourceURL.host) && brand == nil {
            if let siteTitleBrand = extractBrandFromSiteTitle(html: html, sourceURL: sourceURL) {
                brand = siteTitleBrand
            }
        }
        
        // Extract brand from domain as fallback (e.g., "nike.com" -> "Nike")
        // BUT skip this for marketplace sites - they are not brands
        if !isMarketplaceSite(host: sourceURL.host) && brand == nil, let host = sourceURL.host {
            if let domainBrand = extractBrandFromDomain(host) {
                brand = domainBrand
            }
        }
        
        // Extract title from HTML title tag as fallback
        if title == nil {
            title = extractHTMLTitle(html: html)
        }
        
        // Final safety check: Ensure marketplace names are never set as brand
        if let finalBrand = brand {
            let marketplaceNames = ["depop", "poshmark", "mercari", "grailed", "vestiaire", "therealreal",
                                     "thredup", "vinted", "tradesy", "rebag", "fashionphile", "amazon",
                                     "target", "walmart", "ebay", "etsy", "shopify", "bigcommerce"]
            let brandLower = finalBrand.lowercased()
            // Only filter if it's an exact match or starts with the marketplace name (not just contains)
            let isMarketplace = marketplaceNames.contains(where: { 
                brandLower == $0 || brandLower.hasPrefix($0 + " ") || brandLower.hasSuffix(" " + $0)
            })
            if isMarketplace {
                brand = nil
            }
        }
        
        // Extract price from HTML elements if not found yet (site-specific selectors)
        if price == nil {
            if let htmlPrice = extractPriceFromHTMLElements(html: html, baseURL: sourceURL) {
                price = htmlPrice.amount
                priceString = htmlPrice.priceString // Store original price string
                if priceCurrency == nil {
                    priceCurrency = htmlPrice.currency
                }
            }
        }
        
        return ProductMetadata(
            title: title,
            brand: brand,
            category: category,
            price: price,
            priceString: priceString,
            priceCurrency: priceCurrency ?? "USD",
            description: description,
            imageURL: imageURL,
            sourceURL: sourceURL
        )
    }
    
    // MARK: - Parsing Helpers (SwiftSoup-based)
    
    private func extractOGTag(html: String, property: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let metaTags = try doc.select("meta[property=\"\(property)\"]")
            
            if let firstMeta = metaTags.first() {
                let content = try firstMeta.attr("content")
                return content
            }
        } catch {
            // Fallback to regex if SwiftSoup fails
            let pattern = #"<meta\s+property=["']\(property)["']\s+content=["']([^"']+)["']"#
            if let result = extractWithPattern(html: html, pattern: pattern) {
                return result
            }
        }
        return nil
    }
    
    private func extractMetaTag(html: String, name: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let meta = try doc.select("meta[name=\"\(name)\"]").first()
            return try meta?.attr("content")
        } catch {
            // Fallback to regex if SwiftSoup fails
            let pattern = #"<meta\s+name=["']\(name)["']\s+content=["']([^"']+)["']"#
            return extractWithPattern(html: html, pattern: pattern)
        }
    }
    
    private func extractHTMLTitle(html: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            return try doc.title()
        } catch {
            // Fallback to regex if SwiftSoup fails
            let pattern = #"<title[^>]*>([^<]+)</title>"#
            return extractWithPattern(html: html, pattern: pattern)
        }
    }
    
    // Fallback regex extraction method
    private func extractWithPattern(html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractJSONLD(html: String) -> [String: Any]? {
        let pattern = #"<script\s+type=["']application/ld\+json["']>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let jsonRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        
        let jsonString = String(html[jsonRange])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Check if it's a Product type
        if let type = json["@type"] as? String, type == "Product" {
            return json
        }
        
        // Also check if it's in a graph array
        if let graph = json["@graph"] as? [[String: Any]],
           let product = graph.first(where: { $0["@type"] as? String == "Product" }) {
            return product
        }
        
        return nil
    }
    
    // MARK: - Srcset Parsing (SwiftSoup-based)
    
    /// Extracts the largest image URL from srcset attributes in HTML using SwiftSoup
    /// Handles: <picture><source srcset>, <img srcset>, data-srcset, and data-old-hires (Amazon)
    /// Filters out profile/avatar/user icons and prioritizes product images
    private func extractLargestImageFromSrcset(html: String, baseURL: URL) -> URL? {
        do {
            let doc = try SwiftSoup.parse(html)
            var largestURL: URL?
            var largestSize: Int = 0
            
            // Common product container selectors (Mercari, Amazon, etc.)
            let productContainerSelectors = [
                "[class*='product']",
                "[class*='item']",
                "[class*='listing']",
                "[id*='product']",
                "[id*='item']",
                "[data-testid*='product']",
                "[data-testid*='item']",
                "article",
                ".product-image",
                ".item-image",
                ".listing-image"
            ]
            
            // 1. Check <picture><source srcset> inside product containers (highest priority)
            for selector in productContainerSelectors {
                let containers = try doc.select(selector)
                for container in containers {
                    let sources = try container.select("picture source[srcset]")
                    for source in sources {
                        if let srcset = try? source.attr("srcset"),
                           let (url, size) = parseSrcsetString(srcset, baseURL: baseURL),
                           !isProfileOrAvatarURL(url) {
                            if size > largestSize {
                                largestSize = size
                                largestURL = url
                            }
                        }
                    }
                }
            }
            
            // 2. Check <img srcset> inside product containers
            for selector in productContainerSelectors {
                let containers = try doc.select(selector)
                for container in containers {
                    let imgs = try container.select("img[srcset]")
                    for img in imgs {
                        if let srcset = try? img.attr("srcset"),
                           let (url, size) = parseSrcsetString(srcset, baseURL: baseURL),
                           !isProfileOrAvatarURL(url) {
                            if size > largestSize {
                                largestSize = size
                                largestURL = url
                            }
                        }
                    }
                }
            }
            
            // 3. Check data-srcset inside product containers
            for selector in productContainerSelectors {
                let containers = try doc.select(selector)
                for container in containers {
                    let lazyImgs = try container.select("[data-srcset]")
                    for img in lazyImgs {
                        if let srcset = try? img.attr("data-srcset"),
                           let (url, size) = parseSrcsetString(srcset, baseURL: baseURL),
                           !isProfileOrAvatarURL(url) {
                            if size > largestSize {
                                largestSize = size
                                largestURL = url
                            }
                        }
                    }
                }
            }
            
            // 4. Check data-old-hires (Amazon-specific) inside product containers
            for selector in productContainerSelectors {
                let containers = try doc.select(selector)
                for container in containers {
                    let hiresImgs = try container.select("[data-old-hires]")
                    for img in hiresImgs {
                        if let hiresURL = try? img.attr("data-old-hires"),
                           let url = URL(string: hiresURL, relativeTo: baseURL) ?? URL(string: hiresURL),
                           !isProfileOrAvatarURL(url) {
                            // Assume data-old-hires is high-res (assign large size)
                            if 2000 > largestSize {
                                largestSize = 2000
                                largestURL = url
                            }
                        }
                    }
                }
            }
            
            // 5. Fallback: Check all images (not in containers) but still filter profile/avatar URLs
            if largestURL == nil {
                let allSources = try doc.select("picture source[srcset]")
                for source in allSources {
                    if let srcset = try? source.attr("srcset"),
                       let (url, size) = parseSrcsetString(srcset, baseURL: baseURL),
                       !isProfileOrAvatarURL(url) {
                        if size > largestSize {
                            largestSize = size
                            largestURL = url
                        }
                    }
                }
                
                let allImgs = try doc.select("img[srcset]")
                for img in allImgs {
                    if let srcset = try? img.attr("srcset"),
                       let (url, size) = parseSrcsetString(srcset, baseURL: baseURL),
                       !isProfileOrAvatarURL(url) {
                        if size > largestSize {
                            largestSize = size
                            largestURL = url
                        }
                    }
                }
            }
            
            return largestURL
        } catch {
            // Fallback to regex if SwiftSoup fails
            return extractLargestImageFromSrcsetRegex(html: html, baseURL: baseURL)
        }
    }
    
    /// Checks if a URL is likely a profile/avatar/user icon
    private func isProfileOrAvatarURL(_ url: URL) -> Bool {
        let urlString = url.absoluteString.lowercased()
        let excludedPatterns = ["/profile", "/avatar", "/icon", "/user", "/seller", "/member"]
        
        for pattern in excludedPatterns {
            if urlString.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Helper to parse srcset string and return largest URL with size
    private func parseSrcsetString(_ srcsetString: String, baseURL: URL) -> (URL, Int)? {
        var bestURL: URL?
        var bestSize: Int = 0
        
        // Parse srcset: "url1 1x, url2 2x, url3 800w, url4 1200w"
        let candidates = srcsetString.components(separatedBy: ",")
        
        for candidate in candidates {
            let parts = candidate.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces)
            guard let urlString = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlString.isEmpty else {
                continue
            }
            
            // Parse size descriptor (e.g., "800w", "2x", "1x")
            var size: Int = 0
            if parts.count > 1 {
                let descriptor = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if descriptor.hasSuffix("w") {
                    // Width descriptor (e.g., "800w")
                    size = Int(descriptor.replacingOccurrences(of: "w", with: "")) ?? 0
                } else if descriptor.hasSuffix("x") {
                    // Pixel density descriptor (e.g., "2x")
                    // Estimate size based on density (assume base is ~400px)
                    let density = Double(descriptor.replacingOccurrences(of: "x", with: "")) ?? 1.0
                    size = Int(400 * density)
                }
            } else {
                // No descriptor, assume it's a base size
                size = 400
            }
            
            // Resolve relative URLs
            if let url = URL(string: urlString, relativeTo: baseURL) ?? URL(string: urlString) {
                if size > bestSize {
                    bestSize = size
                    bestURL = url
                }
            }
        }
        
        if let url = bestURL, bestSize > 0 {
            return (url, bestSize)
        }
        return nil
    }
    
    /// Fallback regex-based extraction if SwiftSoup fails
    private func extractLargestImageFromSrcsetRegex(html: String, baseURL: URL) -> URL? {
        let pattern = #"<img[^>]+srcset=["']([^"']+)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var largestURL: URL?
        var largestSize: Int = 0
        
        for match in matches {
            guard match.numberOfRanges > 1,
                  let srcsetRange = Range(match.range(at: 1), in: html) else {
                continue
            }
            
            let srcsetString = String(html[srcsetRange])
            if let (url, size) = parseSrcsetString(srcsetString, baseURL: baseURL) {
                if size > largestSize {
                    largestSize = size
                    largestURL = url
                }
            }
        }
        
        return largestURL
    }
    
    // MARK: - Price Extraction from HTML Elements
    
    /// Extracts price from HTML elements using site-specific selectors
    private func extractPriceFromHTMLElements(html: String, baseURL: URL) -> (amount: Decimal?, priceString: String?, currency: String?)? {
        do {
            let doc = try SwiftSoup.parse(html)
            let host = baseURL.host?.lowercased() ?? ""
            
            // Site-specific price selectors
            var priceSelectors: [String] = []
            
            if host.contains("amazon") {
                priceSelectors = [
                    "#priceblock_ourprice",
                    "#priceblock_dealprice",
                    "#priceblock_saleprice",
                    ".a-price .a-offscreen",
                    "[data-a-color='price'] .a-offscreen",
                    ".a-price-whole",
                    "span[data-a-color='price']"
                ]
            } else if host.contains("mercari") {
                priceSelectors = [
                    ".item-price",
                    "[data-testid='price']",
                    ".price",
                    ".itemPrice"
                ]
            } else if host.contains("nordstrom") {
                priceSelectors = [
                    ".current-price",
                    "[data-testid='price']",
                    ".product-price",
                    ".price-current"
                ]
            } else {
                // Generic selectors for other sites
                priceSelectors = [
                    "[data-testid='price']",
                    ".price",
                    ".product-price",
                    ".item-price",
                    ".current-price",
                    "[class*='price']",
                    "[id*='price']"
                ]
            }
            
            // Try each selector
            for selector in priceSelectors {
                if let priceElement = try? doc.select(selector).first() {
                    let priceText = try? priceElement.text()
                    if let priceText = priceText, !priceText.isEmpty {
                        // Extract price and currency
                        if let extracted = parsePriceFromText(priceText) {
                            return (extracted.amount, priceText, extracted.currency) // Return original text to preserve precision
                        }
                    }
                }
            }
            
            // Also check for data attributes
            let dataPriceElements = try doc.select("[data-price], [data-amount], [data-value]")
            for element in dataPriceElements {
                let priceValue = (try? element.attr("data-price")) ?? 
                                (try? element.attr("data-amount")) ?? 
                                (try? element.attr("data-value")) ?? ""
                if !priceValue.isEmpty,
                   let extracted = parsePriceFromText(priceValue) {
                    return (extracted.amount, priceValue, extracted.currency) // Return original value to preserve precision
                }
            }
            
        } catch {
            // Error parsing HTML for price
        }
        
        return nil
    }
    
    /// Parses price text and extracts amount and currency
    private func parsePriceFromText(_ text: String) -> (amount: Decimal?, currency: String?)? {
        // Remove whitespace and common prefixes
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Detect currency
        var currency: String? = nil
        if cleaned.uppercased().contains("USD") || cleaned.contains("$") {
            currency = "USD"
        } else if cleaned.contains("€") || cleaned.uppercased().contains("EUR") {
            currency = "EUR"
        } else if cleaned.contains("£") || cleaned.uppercased().contains("GBP") {
            currency = "GBP"
        } else if cleaned.contains("¥") || cleaned.uppercased().contains("JPY") {
            currency = "JPY"
        } else {
            // Default to USD if no currency detected
            currency = "USD"
        }
        
        // Extract numeric value (remove currency symbols, commas, etc.)
        let cleanedPrice = cleaned.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        
        guard !cleanedPrice.isEmpty, let amount = Decimal(string: cleanedPrice) else {
            return nil
        }
        
        return (amount, currency)
    }
    
    // MARK: - Breadcrumb Extraction
    
    /// Extracts category from breadcrumb navigation (most accurate source)
    /// Breadcrumbs typically show: "Home > Category > Subcategory > Product"
    /// We want the most specific category (usually 2nd or 3rd level)
    private func extractCategoryFromBreadcrumbs(html: String, sourceURL: URL) -> String? {
        // 1. Try JSON-LD BreadcrumbList (most reliable)
        if let breadcrumbCategory = extractCategoryFromJSONLDBreadcrumbs(html: html) {
            return breadcrumbCategory
        }
        
        // 2. Try HTML breadcrumb navigation elements
        if let breadcrumbCategory = extractCategoryFromHTMLBreadcrumbs(html: html) {
            return breadcrumbCategory
        }
        
        // 3. Try extracting from URL path (fallback)
        if let breadcrumbCategory = extractCategoryFromURLPath(sourceURL) {
            return breadcrumbCategory
        }
        
        return nil
    }
    
    /// Extracts category from JSON-LD BreadcrumbList structured data
    private func extractCategoryFromJSONLDBreadcrumbs(html: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let scripts = try doc.select("script[type='application/ld+json']")
            
            for script in scripts {
                guard let jsonString = try? script.html(),
                      let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) else {
                    continue
                }
                
                // Handle single object or array
                if let jsonDict = json as? [String: Any] {
                    if let breadcrumbs = extractBreadcrumbsFromJSON(jsonDict) {
                        return breadcrumbs
                    }
                } else if let jsonArray = json as? [[String: Any]] {
                    for item in jsonArray {
                        if let breadcrumbs = extractBreadcrumbsFromJSON(item) {
                            return breadcrumbs
                        }
                    }
                } else if let graph = (json as? [String: Any])?["@graph"] as? [[String: Any]] {
                    for item in graph {
                        if let breadcrumbs = extractBreadcrumbsFromJSON(item) {
                            return breadcrumbs
                        }
                    }
                }
            }
        } catch {
            // Error parsing breadcrumbs
        }
        
        return nil
    }
    
    /// Extracts breadcrumb category from JSON object
    private func extractBreadcrumbsFromJSON(_ json: [String: Any]) -> String? {
        // Check if this is a BreadcrumbList
        guard let type = json["@type"] as? String, type == "BreadcrumbList" else {
            return nil
        }
        
        guard let itemListElement = json["itemListElement"] as? [[String: Any]] else {
            return nil
        }
        
        // BreadcrumbList items are ordered, we want the most specific category
        // Usually skip first (Home) and last (Product), get 2nd or 3rd
        var categories: [String] = []
        
        for (index, item) in itemListElement.enumerated() {
            guard let name = item["name"] as? String else { continue }
            
            // Skip first item (usually "Home") and last item (usually product name)
            // Get middle items which are usually categories
            if index > 0 && index < itemListElement.count - 1 {
                let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && !cleaned.lowercased().contains("home") {
                    categories.append(cleaned)
                }
            }
        }
        
        // Return the most specific category (last in breadcrumb path)
        // But skip generic ones like "Clothing, Shoes & Accessories"
        let genericCategories = ["clothing", "shoes", "accessories", "apparel", "fashion"]
        for category in categories.reversed() {
            let lowercased = category.lowercased()
            // Skip if it's a generic category that contains multiple items
            if !genericCategories.contains(where: { lowercased.contains($0) && lowercased.contains("&") }) {
                return category
            }
        }
        
        // Fallback: return the last category if no better match
        return categories.last
    }
    
    /// Extracts category from HTML breadcrumb navigation
    private func extractCategoryFromHTMLBreadcrumbs(html: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Try common breadcrumb selectors
            let breadcrumbSelectors = [
                "nav[aria-label*='breadcrumb']",
                "nav[aria-label*='Breadcrumb']",
                "ol.breadcrumb",
                "nav.breadcrumb",
                "[class*='breadcrumb']",
                "[data-testid*='breadcrumb']"
            ]
            
            for selector in breadcrumbSelectors {
                if let breadcrumb = try? doc.select(selector).first() {
                    // Get all links/text in breadcrumb
                    let items = try breadcrumb.select("a, span")
                    var categories: [String] = []
                    
                    for item in items {
                        let text = try item.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            categories.append(text)
                        }
                    }
                    
                    // Filter out generic categories and get most specific
                    let genericCategories = ["clothing", "shoes", "accessories", "apparel", "home"]
                    for category in categories.reversed() {
                        let lowercased = category.lowercased()
                        // Skip generic combined categories like "Clothing, Shoes & Accessories"
                        if !(lowercased.contains("&") && genericCategories.contains(where: { lowercased.contains($0) })) {
                            // Skip if it's just "Home"
                            if !lowercased.contains("home") && category.count > 2 {
                                return category
                            }
                        }
                    }
                    
                    // Fallback: return last non-generic category
                    if let lastCategory = categories.last, !lastCategory.lowercased().contains("home") {
                        return lastCategory
                    }
                }
            }
        } catch {
            // Error parsing HTML breadcrumbs
        }
        
        return nil
    }
    
    /// Extracts category from URL path as fallback
    private func extractCategoryFromURLPath(_ url: URL) -> String? {
        let pathComponents = url.pathComponents.filter { component in
            // Filter out common non-category path components
            !["/", "p", "product", "item", "dp", "id", "A-"].contains(component.lowercased())
        }
        
        // Look for category-like path components
        let categoryKeywords = ["dresses", "tops", "bottoms", "shoes", "accessories", "outerwear", "swimwear", "activewear", "suits"]
        
        for component in pathComponents {
            let lowercased = component.lowercased()
            for keyword in categoryKeywords {
                if lowercased.contains(keyword) {
                    return component.capitalized
                }
            }
        }
        
        return nil
    }
    
    /// Checks if a category is generic (like "Clothing, Shoes & Accessories")
    private func isGenericCategory(_ category: String) -> Bool {
        let lowercased = category.lowercased()
        // Generic categories usually contain "&" or multiple category words
        let genericPatterns = [
            "clothing, shoes",
            "shoes & accessories",
            "accessories &",
            "& accessories",
            "clothing &"
        ]
        return genericPatterns.contains { lowercased.contains($0) }
    }
    
    // MARK: - Brand Extraction
    
    /// Extracts brand from marketplace-specific sources (e.g., Depop aria-label)
    private func extractBrandFromMarketplace(html: String, sourceURL: URL) -> String? {
        // Check if this is a Depop URL (handles depop.com, depop.app.links, etc.)
        guard let host = sourceURL.host else {
            return nil
        }
        
        let isDepop = host.contains("depop.com") || host.contains("depop.app") || host.contains("depop")
        
        guard isDepop else {
            return nil
        }
        
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Method 1: Look for <a aria-label="Brand: [brand], see more...">
            // Target the aria-label and extract text after "Brand:" and before the comma
            let selectors = [
                "a[aria-label*='Brand:']",
                "a[aria-label*='brand:']",
                "a[aria-label*='Brand']",
                "a[aria-label*='brand']"
            ]
            
            var brandLinks: Elements?
            for selector in selectors {
                let links = try? doc.select(selector)
                if let links = links, !links.isEmpty() {
                    brandLinks = links
                    break
                }
            }
            
            if let links = brandLinks {
                for link in links {
                    if let ariaLabel = try? link.attr("aria-label") {
                        print("🔍 DEBUG: Detected aria-label from product webpage: '\(ariaLabel)'")
                        
                        // Parse: "Brand: Express, see more items from this brand" -> "Express"
                        // Extract text after "Brand:" and before the comma
                        let lowerAriaLabel = ariaLabel.lowercased()
                        if lowerAriaLabel.contains("brand:") {
                            // Find the position of "Brand:" (case insensitive)
                            if let brandColonRange = ariaLabel.range(of: "Brand:", options: .caseInsensitive) {
                                // Get text after "Brand:"
                                let afterBrandColon = String(ariaLabel[brandColonRange.upperBound...])
                                // Split by comma to get just the brand name
                                let brandPart = afterBrandColon.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                if let brandName = brandPart, !brandName.isEmpty {
                                    print("✅ DEBUG: Extracted brand name from aria-label: '\(brandName)'")
                                    return brandName
                                }
                            }
                        }
                    }
                }
            }
            
            // Method 2: Look for brand in link text or data attributes
            let allLinks = try doc.select("a")
            for link in allLinks {
                // Check data attributes
                let dataBrand = try? link.attr("data-brand")
                if let brand = dataBrand, !brand.isEmpty {
                    return brand
                }
            }
            
            // Method 3: Look for brand in specific Depop selectors
            let brandSelectors = [
                "[data-testid*='brand']",
                "[class*='brand']",
                ".brand",
                "[data-brand]"
            ]
            
            for selector in brandSelectors {
                let elements = try? doc.select(selector)
                if let elems = elements, !elems.isEmpty() {
                    for elem in elems {
                        let dataBrand = try? elem.attr("data-brand")
                        if let brand = dataBrand, !brand.isEmpty {
                            return brand
                        }
                    }
                }
            }
        } catch {
            // Error parsing HTML
        }
        
        return nil
    }
    
    /// Extracts brand from site title (more accurate than domain)
    /// IMPORTANT: This should NOT be used for marketplace sites - they are not brands
    private func extractBrandFromSiteTitle(html: String, sourceURL: URL) -> String? {
        // Get the site title
        guard let siteTitle = extractOGTag(html: html, property: "og:site_name") ?? 
                              extractHTMLTitle(html: html) else {
            return nil
        }
        
        // CRITICAL: Skip marketplace/shopping site titles FIRST - these aren't brands
        let marketplaceNames = ["depop", "poshmark", "mercari", "grailed", "vestiaire", "therealreal",
                                 "thredup", "vinted", "tradesy", "rebag", "fashionphile", "amazon",
                                 "target", "walmart", "ebay", "etsy", "shopify", "bigcommerce"]
        let titleLower = siteTitle.lowercased()
        if marketplaceNames.contains(where: { titleLower.contains($0) }) {
            return nil
        }
        
        // Common patterns in site titles:
        // "H&M | Shop Online" -> "H&M"
        // "Nike. Just Do It." -> "Nike"
        // "ZARA United States" -> "ZARA"
        // "adidas Official Website" -> "adidas"
        
        let title = siteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        
        // Split by common separators (try each separator and take the first meaningful part)
        let separators = ["|", "•", "—", "–", " - ", " · ", "·"]
        var firstPart = title
        
        // Find the first separator and split on it
        for separator in separators {
            if let range = title.range(of: separator) {
                firstPart = String(title[..<range.lowerBound])
                break
            }
        }
        
        // Clean up the first part
        firstPart = firstPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstPart.isEmpty else { return nil }
        
        // Remove common suffixes
        let cleaned = firstPart
            .replacingOccurrences(of: " Official Website", with: "", options: [.caseInsensitive], range: nil)
            .replacingOccurrences(of: " Official", with: "", options: [.caseInsensitive], range: nil)
            .replacingOccurrences(of: " United States", with: "", options: [.caseInsensitive], range: nil)
            .replacingOccurrences(of: " US", with: "", options: [.caseInsensitive], range: nil)
            .replacingOccurrences(of: " USA", with: "", options: [.caseInsensitive], range: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip if it's too long (probably not a brand name) or too short
        guard cleaned.count > 1 && cleaned.count <= 50 else {
            return nil
        }
        
        return cleaned
    }
    
    private func extractBrandFromDomain(_ host: String) -> String? {
        guard !host.isEmpty else { return nil }
        
        // Remove www, www2, www3, etc. and other common subdomains
        var domain = host.lowercased()
        
        // Remove common subdomain patterns (www, www2, www3, etc.)
        let subdomainPattern = #"^(www\d*|shop|store|shop-|store-|www-|m|mobile|app)\.?"#
        if let regex = try? NSRegularExpression(pattern: subdomainPattern, options: .caseInsensitive) {
            let nsString = domain as NSString
            let range = NSRange(location: 0, length: nsString.length)
            domain = regex.stringByReplacingMatches(in: domain, options: [], range: range, withTemplate: "")
        }
        
        // Remove leading/trailing dots
        domain = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !domain.isEmpty else { return nil }
        
        // Extract main domain (part before first dot)
        if let firstDot = domain.firstIndex(of: ".") {
            domain = String(domain[..<firstDot])
        }
        
        guard !domain.isEmpty else { return nil }
        
        // Skip common shopping domains that aren't brands
        let shoppingDomains = ["amazon", "target", "walmart", "ebay", "etsy", "shopify", "bigcommerce"]
        if shoppingDomains.contains(domain) {
            return nil
        }
        
        // Handle special cases
        let brandMappings: [String: String] = [
            "hm": "H&M",
            "zara": "ZARA",
            "nike": "Nike",
            "adidas": "adidas",
            "puma": "PUMA",
            "gap": "Gap",
            "oldnavy": "Old Navy",
            "bananarepublic": "Banana Republic",
            "athleta": "Athleta"
        ]
        
        if let mappedBrand = brandMappings[domain] {
            return mappedBrand
        }
        
        // Capitalize appropriately (handle cases like "H&M" which should stay as is)
        // For simple domains, capitalize first letter
        // Check if it's all uppercase (like ZARA, H&M domains might be)
        if domain == domain.uppercased() && domain.count <= 5 {
            return domain.uppercased()
        }
        // Otherwise capitalize first letter
        return domain.capitalized
    }
    
    // MARK: - Image Fetching
    
    /// Fetches image data from URL with validation
    func fetchImageData(from url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0
        configuration.timeoutIntervalForResource = 20.0
        
        // Create request with headers to request high-quality image
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MetadataError.networkError
        }
        
        // Validate MIME type
        if let mimeType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            let validMimeTypes = ["image/jpeg", "image/jpg", "image/png", "image/webp", "image/gif", "image/heic", "image/heif"]
            let isValid = validMimeTypes.contains { mimeType.lowercased().contains($0.replacingOccurrences(of: "image/", with: "")) }
            if !isValid {
                throw MetadataError.invalidImageData("Invalid MIME type: \(mimeType)")
            }
        }
        
        // Validate minimum size (at least 1KB)
        guard data.count >= 1024 else {
            throw MetadataError.invalidImageData("Image data too small: \(data.count) bytes (minimum 1KB)")
        }
        
        // Validate pixel dimensions by creating UIImage
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            throw MetadataError.invalidImageData("Data is not valid image data")
        }
        
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        
        // Minimum dimension threshold (100x100 pixels)
        guard pixelWidth >= 100 && pixelHeight >= 100 else {
            throw MetadataError.invalidImageData("Image too small: \(pixelWidth)x\(pixelHeight) pixels (minimum 100x100)")
        }
        
        return data
    }
    
    /// Fetches image from URL (legacy method, kept for compatibility)
    func fetchImage(from url: URL) async throws -> UIImage? {
        let data = try await fetchImageData(from: url)
        guard let image = UIImage(data: data) else {
            return nil
        }
        
        return image
    }
    
    enum MetadataError: Error {
        case invalidHTML
        case networkError
        case invalidImageData(String) // Detailed error message
        case webViewTimeout
    }
}

// MARK: - WKWebView HTML Extractor

private class WebViewHTMLExtractor: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private let continuation: CheckedContinuation<String, Error>
    private var hasCompleted = false
    private var timeoutTask: Task<Void, Never>?
    
    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
        super.init()
        
        // Set timeout of 15 seconds
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            if !self.hasCompleted {
                self.hasCompleted = true
                continuation.resume(throwing: ProductMetadataService.MetadataError.webViewTimeout)
                self.cleanup()
            }
        }
    }
    
    func extractHTML(from url: URL) {
        // Use a non-displaying WKWebView configuration
        let config = WKWebViewConfiguration()
        
        // CRITICAL: Set custom User-Agent to get the full page, not the app redirect
        // Using Safari iOS user agent to appear as a real browser
        config.applicationNameForUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
        
        // IMPORTANT: Also set custom User-Agent in the request headers
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        
        // Add additional headers to appear more like a real browser
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        
        webView?.load(request)
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasCompleted else { return }
        
        // Wait for JavaScript to fully render the page (especially for dynamic og:image tags)
        // Don't extract HTML immediately - wait for JS to render
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, !self.hasCompleted else { return }
            
            // Extract HTML after JavaScript has executed
            // Using document.documentElement.outerHTML to get the full rendered HTML
            webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [weak self] result, error in
                guard let self = self, !self.hasCompleted else { return }
                
                if let error = error {
                    self.hasCompleted = true
                    self.timeoutTask?.cancel()
                    self.continuation.resume(throwing: error)
                    self.cleanup()
                    return
                }
                
                if let html = result as? String {
                    // Check if we got the actual product page or just the redirect shell
                    // Look for Open Graph tags to verify the page has fully rendered
                    let hasOGImage = html.contains("og:image") || html.contains("property=\"og:image\"")
                    let hasOGTitle = html.contains("og:title") || html.contains("property=\"og:title\"")
                    
                    if hasOGImage && hasOGTitle {
                        self.hasCompleted = true
                        self.timeoutTask?.cancel()
                        self.continuation.resume(returning: html)
                        self.cleanup()
                    } else {
                        // Try again with longer delay to wait for JavaScript to finish
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            guard let self = self, !self.hasCompleted else { return }
                            
                            webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [weak self] result2, error2 in
                                guard let self = self, !self.hasCompleted else { return }
                                
                                if let error2 = error2 {
                                    // Return the first HTML even if incomplete
                                    self.hasCompleted = true
                                    self.timeoutTask?.cancel()
                                    self.continuation.resume(returning: html)
                                    self.cleanup()
                                    return
                                }
                                
                                if let html2 = result2 as? String {
                                    self.hasCompleted = true
                                    self.timeoutTask?.cancel()
                                    self.continuation.resume(returning: html2)
                                } else {
                                    // Return the first HTML if retry fails
                                    self.hasCompleted = true
                                    self.timeoutTask?.cancel()
                                    self.continuation.resume(returning: html)
                                }
                                
                                self.cleanup()
                            }
                        }
                    }
                } else {
                    self.hasCompleted = true
                    self.timeoutTask?.cancel()
                    self.continuation.resume(throwing: ProductMetadataService.MetadataError.invalidHTML)
                    self.cleanup()
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        timeoutTask?.cancel()
        continuation.resume(throwing: error)
        cleanup()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        timeoutTask?.cancel()
        continuation.resume(throwing: error)
        cleanup()
    }
    
    private func cleanup() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }
}

