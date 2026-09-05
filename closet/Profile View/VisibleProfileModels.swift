//
//  VisibleProfileModels.swift
//  closet
//
//  Decodable models for public profile RPCs (friend / remote profile viewing).
//

import Foundation

struct VisibleWardrobe: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: String?
    let visibility: String
    let isDefault: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, type, visibility
        case isDefault = "is_default"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        visibility = try c.decode(String.self, forKey: .visibility)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    init(
        id: UUID,
        name: String,
        type: String?,
        visibility: String,
        isDefault: Bool = false,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.visibility = visibility
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    var wardrobeType: String {
        (type ?? "closet").lowercased()
    }

    var typeHeading: String {
        wardrobeType == "wishlist" ? "WISHLIST" : "CLOSET"
    }

    var wardrobeVisibility: WardrobeVisibility {
        WardrobeVisibility(rawValue: visibility) ?? .public
    }
}

struct VisibleWardrobeItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String?
    let thumbnailUrl: String?
    let imageUrl: String?
    let createdAt: Date?
    let brandName: String?
    let categoryName: String?
    let subcategoryName: String?
    let sizeValue: String?

    enum CodingKeys: String, CodingKey {
        case id = "item_id"
        case name
        case thumbnailUrl = "thumbnail_url"
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case brandName = "brand_name"
        case categoryName = "category_name"
        case subcategoryName = "subcategory_name"
        case sizeValue = "size_value"
    }

    init(
        id: UUID,
        name: String?,
        thumbnailUrl: String?,
        imageUrl: String?,
        createdAt: Date? = nil,
        brandName: String? = nil,
        categoryName: String? = nil,
        subcategoryName: String? = nil,
        sizeValue: String? = nil
    ) {
        self.id = id
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.imageUrl = imageUrl
        self.createdAt = createdAt
        self.brandName = brandName
        self.categoryName = categoryName
        self.subcategoryName = subcategoryName
        self.sizeValue = sizeValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        brandName = try c.decodeIfPresent(String.self, forKey: .brandName)
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        subcategoryName = try c.decodeIfPresent(String.self, forKey: .subcategoryName)
        sizeValue = try c.decodeIfPresent(String.self, forKey: .sizeValue)
    }

    var displayImageURL: URL? {
        let raw = thumbnailUrl ?? imageUrl
        guard let raw, let url = URL(string: raw) else { return nil }
        return url
    }
}

struct VisibleWardrobeOutfit: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String?
    let imageUrl: String?
    let wornImageUrl: String?
    let createdAt: Date?
    let categoryName: String?
    /// Set for pending Redress suggestions shown to the suggester on the recipient profile.
    var suggesterUserId: UUID?
    var suggesterUsername: String?
    var suggesterDisplayName: String?
    var suggesterAvatarUrl: String?
    var isPendingSuggestion: Bool

    enum CodingKeys: String, CodingKey {
        case id = "outfit_id"
        case name
        case imageUrl = "image_url"
        case wornImageUrl = "worn_image_url"
        case createdAt = "created_at"
        case categoryName = "category_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        wornImageUrl = try c.decodeIfPresent(String.self, forKey: .wornImageUrl)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        suggesterUserId = nil
        suggesterUsername = nil
        suggesterDisplayName = nil
        suggesterAvatarUrl = nil
        isPendingSuggestion = false
    }

    init(
        id: UUID,
        name: String?,
        imageUrl: String?,
        wornImageUrl: String?,
        createdAt: Date? = nil,
        categoryName: String? = nil,
        suggesterUserId: UUID? = nil,
        suggesterUsername: String? = nil,
        suggesterDisplayName: String? = nil,
        suggesterAvatarUrl: String? = nil,
        isPendingSuggestion: Bool = false
    ) {
        self.id = id
        self.name = name
        self.imageUrl = imageUrl
        self.wornImageUrl = wornImageUrl
        self.createdAt = createdAt
        self.categoryName = categoryName
        self.suggesterUserId = suggesterUserId
        self.suggesterUsername = suggesterUsername
        self.suggesterDisplayName = suggesterDisplayName
        self.suggesterAvatarUrl = suggesterAvatarUrl
        self.isPendingSuggestion = isPendingSuggestion
    }

    var collageImageURL: URL? {
        guard let imageUrl, let url = URL(string: imageUrl) else { return nil }
        return url
    }

    var suggesterAvatarImageURL: URL? {
        guard let suggesterAvatarUrl, let url = URL(string: suggesterAvatarUrl) else { return nil }
        return url
    }
}

struct RecipientDuplicateOutfit: Decodable, Identifiable, Hashable {
    let outfitId: UUID
    let name: String?
    let imageUrl: String?
    let wardrobeId: UUID?

    var id: UUID { outfitId }

    enum CodingKeys: String, CodingKey {
        case outfitId = "outfit_id"
        case name
        case imageUrl = "image_url"
        case wardrobeId = "wardrobe_id"
    }

    var collageImageURL: URL? {
        guard let imageUrl, let url = URL(string: imageUrl) else { return nil }
        return url
    }

    var canNavigateToDetail: Bool {
        wardrobeId != nil
    }
}

enum RedressSuggestionViewerRole: Hashable {
    case recipient
    case submitter
}

struct PendingRedressNavigationDestination: Hashable, Identifiable {
    let recipientUserId: UUID
    let wardrobeId: UUID
    let suggestionSummary: VisibleWardrobeOutfit
    let viewerRole: RedressSuggestionViewerRole

    var id: UUID { suggestionSummary.id }
}

struct VisibleOutfitSuggestion: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String?
    let imageUrl: String?
    let suggesterUserId: UUID?
    let suggesterUsername: String?
    let suggesterDisplayName: String?
    let suggesterAvatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id = "suggestion_id"
        case name
        case imageUrl = "image_url"
        case suggesterUserId = "suggester_user_id"
        case suggesterUsername = "suggester_username"
        case suggesterDisplayName = "suggester_display_name"
        case suggesterAvatarUrl = "suggester_avatar_url"
    }

    func asGridOutfit() -> VisibleWardrobeOutfit {
        VisibleWardrobeOutfit(
            id: id,
            name: name,
            imageUrl: imageUrl,
            wornImageUrl: nil,
            suggesterUserId: suggesterUserId,
            suggesterUsername: suggesterUsername,
            suggesterDisplayName: suggesterDisplayName,
            suggesterAvatarUrl: suggesterAvatarUrl,
            isPendingSuggestion: true
        )
    }
}

struct VisibleItemPhoto: Decodable, Identifiable, Hashable {
    let imageUrl: String?
    let thumbnailUrl: String?
    let type: String?
    let isPrimary: Bool

    var id: String { "\(type ?? "photo")-\(imageUrl ?? thumbnailUrl ?? "")" }

    enum CodingKeys: String, CodingKey {
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case type
        case isPrimary = "is_primary"
    }

    init(imageUrl: String?, thumbnailUrl: String?, type: String?, isPrimary: Bool) {
        self.imageUrl = imageUrl
        self.thumbnailUrl = thumbnailUrl
        self.type = type
        self.isPrimary = isPrimary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        isPrimary = try c.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
    }

    /// Prefer full-resolution `imageUrl` for detail heroes; fall back to thumbnail.
    var displayURL: URL? {
        let raw = imageUrl ?? thumbnailUrl
        guard let raw, let url = URL(string: raw) else { return nil }
        return url
    }
}

struct VisibleItemDetail: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String?
    let notes: String?
    let brandName: String?
    let categoryName: String?
    let subcategoryName: String?
    let sizeValue: String?
    let photos: [VisibleItemPhoto]
    let pairedItems: [VisibleWardrobeItem]
    let outfits: [VisibleWardrobeOutfit]
    let links: [VisibleItemLink]

    enum CodingKeys: String, CodingKey {
        case id = "item_id"
        case name, notes, photos
        case brandName = "brand_name"
        case categoryName = "category_name"
        case subcategoryName = "subcategory_name"
        case sizeValue = "size_value"
        case pairedItems = "paired_items"
        case outfits
        case links
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        brandName = try c.decodeIfPresent(String.self, forKey: .brandName)
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        subcategoryName = try c.decodeIfPresent(String.self, forKey: .subcategoryName)
        sizeValue = try c.decodeIfPresent(String.self, forKey: .sizeValue)
        photos = try c.decodeIfPresent([VisibleItemPhoto].self, forKey: .photos) ?? []
        pairedItems = try c.decodeIfPresent([VisibleWardrobeItem].self, forKey: .pairedItems) ?? []
        outfits = try c.decodeIfPresent([VisibleWardrobeOutfit].self, forKey: .outfits) ?? []
        links = try c.decodeIfPresent([VisibleItemLink].self, forKey: .links) ?? []
    }
}

struct VisibleItemLink: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String?
    let url: String?
    let type: String?
    let visibility: String?

    enum CodingKeys: String, CodingKey {
        case id, name, url, type, visibility
    }

    var itemLinkType: ItemLinkType {
        ItemLinkType.resolving(type)
    }

    var itemLinkVisibility: WardrobeVisibility {
        WardrobeVisibility(rawValue: visibility ?? "") ?? itemLinkType.defaultVisibility
    }

    var urlValue: URL? {
        guard let url, let parsed = URL(string: url) else { return nil }
        return parsed
    }
}

struct VisibleOutfitItemThumb: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String?
    let thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case id = "item_id"
        case name
        case thumbnailUrl = "thumbnail_url"
    }

    var displayURL: URL? {
        guard let thumbnailUrl, let url = URL(string: thumbnailUrl) else { return nil }
        return url
    }
}

struct VisibleOutfitDetail: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String?
    let notes: String?
    let imageUrl: String?
    let wornImageUrl: String?
    let createdAt: Date?
    let itemThumbnails: [VisibleOutfitItemThumb]

    enum CodingKeys: String, CodingKey {
        case id = "outfit_id"
        case name, notes
        case imageUrl = "image_url"
        case wornImageUrl = "worn_image_url"
        case createdAt = "created_at"
        case itemThumbnails = "item_thumbnails"
    }
}

struct VisibleOutfitSuggestionDetail: Decodable, Identifiable, Hashable {
    let id: UUID
    let proposedName: String?
    let proposedNotes: String?
    let imageUrl: String?
    let createdAt: Date?
    let itemThumbnails: [VisibleOutfitItemThumb]

    enum CodingKeys: String, CodingKey {
        case id = "suggestion_id"
        case proposedName = "proposed_name"
        case proposedNotes = "proposed_notes"
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case itemThumbnails = "item_thumbnails"
    }

    var collageImageURL: URL? {
        guard let imageUrl, let url = URL(string: imageUrl) else { return nil }
        return url
    }
}

extension PublicUserProfile: Hashable {
    static func == (lhs: PublicUserProfile, rhs: PublicUserProfile) -> Bool {
        lhs.userId == rhs.userId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
    }
}
