//
//  SyncTypes.swift
//  closet
//

import Foundation

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case notAuthenticated
    case noContext
    case uploadFailed
    case networkError
    /// Raw `photo.data` could not be decoded and exceeded the worker size limit.
    case photoExceedsWorkerLimit
    /// Could not re-encode image bytes for R2 upload.
    case photoEncodingFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .noContext:
            return "Core Data context not set"
        case .uploadFailed:
            return "Failed to upload photo"
        case .networkError:
            return "Network error during sync"
        case .photoExceedsWorkerLimit:
            return "Photo file is too large for upload and could not be compressed"
        case .photoEncodingFailed:
            return "Failed to compress photo for upload"
        }
    }
}

// MARK: - Codable Structs for Sync

/// Codable struct for syncing item data
struct SyncItemData: Codable {
    let id: String
    let userId: String
    let name: String
    let notes: String?
    let isFavorite: Bool
    // isWishlist removed - replaced by item_wardrobes junction table
    let isDraft: Bool
    let minTemperature: Double?
    let maxTemperature: Double?
    let temperatureUnit: String?
    let weight: Double?
    let weightUnit: String?
    let isSoftDeleted: Bool
    let createdAt: String?
    let wishedAt: String?
    let purchasedAt: String?
    let updatedAt: String?
    let brandId: String?
    let categoryId: String?
    let subcategoryId: String?
    let sizeId: String?
    let locationId: String?
    let linkSectionVisibility: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case notes
        case isFavorite = "is_favorite"
        // isWishlist removed - replaced by item_wardrobes junction table
        case isDraft = "is_draft"
        case minTemperature = "min_temperature"
        case maxTemperature = "max_temperature"
        case temperatureUnit = "temperature_unit"
        case weight
        case weightUnit = "weight_unit"
        case isSoftDeleted = "is_soft_deleted"
        case createdAt = "created_at"
        case wishedAt = "wished_at"
        case purchasedAt = "purchased_at"
        case updatedAt = "updated_at"
        case brandId = "brand_id"
        case categoryId = "category_id"
        case subcategoryId = "subcategory_id"
        case sizeId = "size_id"
        case locationId = "location_id"
        case linkSectionVisibility = "link_section_visibility"
    }
}

/// Codable struct for syncing photo data
struct SyncPhotoData: Codable {
    let id: String
    let itemId: String
    let userId: String
    let imageUrl: String?
    let isPrimary: Bool
    let type: String?
    let createdAt: String?
    let thumbnailUrl: String?
    let timestamp: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case itemId = "item_id"
        case userId = "user_id"
        case imageUrl = "image_url"
        case isPrimary = "is_primary"
        case type
        case createdAt = "created_at"
        case thumbnailUrl = "thumbnail_url"
        case timestamp
        case updatedAt = "updated_at"
    }
}

/// Codable structs for junction tables
struct ItemColorJunction: Codable {
    let itemId: String
    let colorId: String
 //   let userId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case colorId = "color_id"
      //  case userId = "user_id"
    }
}

struct ItemSeasonJunction: Codable {
    let itemId: String
    let seasonId: String
  //  let userId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case seasonId = "season_id"
      //  case userId = "user_id"
    }
}

struct ItemTagJunction: Codable {
    let itemId: String
    let tagId: String
  //  let userId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case tagId = "tag_id"
      //  case userId = "user_id"
    }
}

struct ItemWardrobeJunction: Codable {
    let itemId: String
    let wardrobeId: String
  //  let userId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case wardrobeId = "wardrobe_id"
      //  case userId = "user_id"
    }
}

struct ItemPairJunction: Codable {
    let itemId: String
    let pairedItemId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case pairedItemId = "paired_item_id"
    }
}

struct ItemPairResponse: Codable {
    let pairedItemId: String
    
    enum CodingKeys: String, CodingKey {
        case pairedItemId = "paired_item_id"
    }
}

struct ItemLinkResponse: Codable {
    let id: String
    
    enum CodingKeys: String, CodingKey {
        case id
    }
}

struct ItemPhotoResponse: Codable {
    let id: String
    
    enum CodingKeys: String, CodingKey {
        case id
    }
}

struct ItemColorResponse: Codable {
    let colorId: String
    
    enum CodingKeys: String, CodingKey {
        case colorId = "color_id"
    }
}

struct ItemSeasonResponse: Codable {
    let seasonId: String
    
    enum CodingKeys: String, CodingKey {
        case seasonId = "season_id"
    }
}

struct ItemTagResponse: Codable {
    let tagId: String
    
    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
    }
}

struct ItemWardrobeResponse: Codable {
    let wardrobeId: String
    
    enum CodingKeys: String, CodingKey {
        case wardrobeId = "wardrobe_id"
    }
}

struct SyncPriceData: Codable {
    let itemId: String      // Primary key — one price per item
    let amount: Decimal
    let currency: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case amount
        case currency
    }
}

struct SyncLinkData: Codable {
    let id: String
    let itemId: String
  //  let userId: String
    let name: String?
    let url: String?
    let type: String
    let visibility: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case itemId = "item_id"
       // case userId = "user_id"
        case name
        case url
        case type
        case visibility
    }
}

// MARK: - Reference Data Codable Structs

struct SyncBrandData: Codable {
    let id: String
    let userId: String
    let name: String
    let isVisible: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case isVisible = "is_visible"
    }
}

struct SyncCategoryData: Codable {
    let id: String
    let userId: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
    }
}

struct SyncSubcategoryData: Codable {
    let id: String
    let categoryId: String
    let userId: String
    let name: String
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case userId = "user_id"
        case name
        case sortOrder = "sort_order"
    }
}

struct SyncColorData: Codable {
    let id: String
    let userId: String
    let name: String
    let hexCode: String?
    let isVisible: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case hexCode = "hex_code"
        case isVisible = "is_visible"
    }
}

struct SyncSeasonData: Codable {
    let id: String
    let userId: String
    let name: String
    let isVisible: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case isVisible = "is_visible"
    }
}

struct SyncSizeData: Codable {
    let id: String
    let categoryId: String? // Optional - sizes are now independent of categories
    let userId: String
    let value: String
    let scale: String?
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case userId = "user_id"
        case value
        case scale
        case sortOrder = "sort_order"
    }
}

struct SyncTagData: Codable {
    let id: String
    let userId: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
    }
}

struct SyncOutfitCategoryData: Codable {
    let id: String
    let userId: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
    }
}

struct SyncPackingChecklistSectionData: Codable {
    let id: String
    let userId: String
    let wardrobeId: String
    let kind: Int
    let title: String
    let sortIndex: Int
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case wardrobeId = "wardrobe_id"
        case kind
        case title
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SyncPackingChecklistItemData: Codable {
    let id: String
    let userId: String
    let wardrobeId: String
    let sectionId: String?
    let kind: Int
    let checklistText: String
    let isCompleted: Bool
    let sortIndex: Int
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case wardrobeId = "wardrobe_id"
        case sectionId = "section_id"
        case kind
        case checklistText = "checklist_text"
        case isCompleted = "is_completed"
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SyncLocationData: Codable {
    let id: String
    let userId: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
    }
}

struct SyncWardrobeData: Codable {
    let id: String
    let userId: String
    let name: String
    let type: String?
    let visibility: String
    let isSoftDeleted: Bool
    let isDefault: Bool
    let packingChecklistSectionTitle: String
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case visibility
        case isSoftDeleted = "is_soft_deleted"
        case isDefault = "is_default"
        case packingChecklistSectionTitle = "packing_checklist_section_title"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SyncOutfitData: Codable {
    let id: String
    let userId: String
    let name: String?
    let notes: String?
    let isFavorite: Bool
    let isDraft: Bool
    let isSoftDeleted: Bool
    let categoryId: String?
    let createdAt: String?
    let updatedAt: String?
    let imageUrl: String?          // R2 CDN URL of the pre-rendered collage
    let wornImageUrl: String?      // R2 CDN URL of the "worn" photo
    let transformationJson: String? // JSON string of [SavedOutfitItem] with portable UUIDs

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case notes
        case isFavorite = "is_favorite"
        case isDraft = "is_draft"
        case isSoftDeleted = "is_soft_deleted"
        case categoryId = "category_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case imageUrl = "image_url"
        case wornImageUrl = "worn_image_url"
        case transformationJson = "transformation_json"
    }
}

struct OutfitItemJunction: Codable {
    let outfitId: String
    let itemId: String

    enum CodingKeys: String, CodingKey {
        case outfitId = "outfit_id"
        case itemId = "item_id"
    }
}

struct OutfitTagJunction: Codable {
    let outfitId: String
    let tagId: String

    enum CodingKeys: String, CodingKey {
        case outfitId = "outfit_id"
        case tagId = "tag_id"
    }
}

struct OutfitItemResponse: Codable {
    let itemId: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
    }
}

struct OutfitTagResponse: Codable {
    let tagId: String

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
    }
}

// MARK: - Calendar events

struct SyncEventData: Codable {
    let id: String
    let userId: String
    let name: String?
    let notes: String?
    let location: String?
    let fullAddress: String?
    let latitude: Double
    let longitude: Double
    let startDate: String?
    let endDate: String?
    let date: String?
    let time: String?
    let timestamp: String?
    let visibility: String
    let isSoftDeleted: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case notes
        case location
        case fullAddress = "full_address"
        case latitude
        case longitude
        case startDate = "start_date"
        case endDate = "end_date"
        case date
        case time
        case timestamp
        case visibility
        case isSoftDeleted = "is_soft_deleted"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct EventItemJunction: Codable {
    let eventId: String
    let itemId: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case itemId = "item_id"
        case sortOrder = "sort_order"
    }
}

struct EventOutfitJunction: Codable {
    let eventId: String
    let outfitId: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case outfitId = "outfit_id"
    }
}

struct EventItemResponse: Codable {
    let itemId: String
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case sortOrder = "sort_order"
    }
}

struct EventOutfitResponse: Codable {
    let outfitId: String

    enum CodingKeys: String, CodingKey {
        case outfitId = "outfit_id"
    }
}

struct RemoteEventRow: Codable {
    let id: String
    let userId: String
    let name: String?
    let notes: String?
    let location: String?
    let fullAddress: String?
    let latitude: Double?
    let longitude: Double?
    let startDate: String?
    let endDate: String?
    let date: String?
    let time: String?
    let timestamp: String?
    let visibility: String?
    let isSoftDeleted: Bool?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case notes
        case location
        case fullAddress = "full_address"
        case latitude
        case longitude
        case startDate = "start_date"
        case endDate = "end_date"
        case date
        case time
        case timestamp
        case visibility
        case isSoftDeleted = "is_soft_deleted"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SyncUserProfileData: Codable {
    let userId: String
    let weightKg: Double?
    let weightUnit: String?
    let username: String?
    let displayName: String?
    let styleTags: [String]?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case weightKg = "weight_kg"
        case weightUnit = "weight_unit"
        case username
        case displayName = "display_name"
        case styleTags = "style_tags"
        case updatedAt = "updated_at"
    }
}


// MARK: - Date Extension

extension Date {
    var ISO8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    /// Parses Supabase / sync timestamps (with or without fractional seconds).
    static func fromISO8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

