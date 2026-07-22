//
//  OutfitSuggestionMaterializer.swift
//  closet
//
//  Converts a pending Supabase Redress outfit suggestion into a local Core Data Outfit
//  so the recipient can edit it in OutfitDetailView.
//

import CoreData
import Foundation
import UIKit

enum OutfitSuggestionMaterializer {
    enum MaterializeError: LocalizedError {
        case notAuthenticated
        case suggestionUnavailable
        case notRecipient
        case noItemsFound
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Sign in to view this outfit suggestion."
            case .suggestionUnavailable:
                return "This outfit suggestion is no longer available."
            case .notRecipient:
                return "This outfit suggestion is not for your account."
            case .noItemsFound:
                return "Could not find the items for this outfit in your closet."
            case .saveFailed(let message):
                return "Failed to save outfit: \(message)"
            }
        }
    }

    @MainActor
    static func materializeOutfitSuggestion(
        suggestionId: UUID,
        recipientUserId: UUID,
        in context: NSManagedObjectContext,
        supabaseService: SupabaseService
    ) async throws -> Outfit {
        if let existing = fetchExistingMaterializedOutfit(
            suggestionId: suggestionId,
            userId: recipientUserId,
            in: context
        ) {
            return existing
        }

        let record = try await supabaseService.fetchOutfitSuggestionForMaterialization(
            suggestionId: suggestionId
        )

        guard record.status == "pending" || record.status == "accepted" else {
            throw MaterializeError.suggestionUnavailable
        }
        guard record.recipientUserId == recipientUserId else {
            throw MaterializeError.notRecipient
        }

        let items = try fetchLocalItems(
            ids: record.itemIds,
            userId: recipientUserId,
            in: context
        )

        let outfit = Outfit(context: context)
        outfit.id = suggestionId
        outfit.userId = recipientUserId.uuidString
        outfit.isDraft = false
        outfit.isSoftDeleted = false
        outfit.isFavorite = false
        outfit.name = record.proposedName
        outfit.notes = record.proposedNotes
        outfit.timestamp = record.createdAt ?? Date()
        outfit.createdAt = record.createdAt ?? Date()
        outfit.redressSuggestedAt = record.createdAt ?? Date()
        setUpdatedAt(outfit)

        for item in items {
            outfit.addToItems(item)
        }

        if let transformationData = record.transformationData(fallbackItemIds: items) {
            outfit.transformationData = transformationData
        }

        if let imageURLString = record.imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !imageURLString.isEmpty,
           let url = URL(string: imageURLString),
           let imageData = try? await downloadProcessedImageData(from: url) {
            outfit.image = imageData
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw MaterializeError.saveFailed(error.localizedDescription)
        }

        return outfit
    }

    @MainActor
    static func deleteMaterializedOutfitIfExists(
        suggestionId: UUID,
        recipientUserId: UUID,
        in context: NSManagedObjectContext
    ) {
        guard let existing = fetchExistingMaterializedOutfit(
            suggestionId: suggestionId,
            userId: recipientUserId,
            in: context
        ) else {
            return
        }
        context.delete(existing)
        try? context.save()
    }

    @MainActor
    private static func fetchExistingMaterializedOutfit(
        suggestionId: UUID,
        userId: UUID,
        in context: NSManagedObjectContext
    ) -> Outfit? {
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", suggestionId as CVarArg),
            NSPredicate(format: "userId == %@", userId.uuidString),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])
        return try? context.fetch(request).first
    }

    @MainActor
    private static func fetchLocalItems(
        ids: [UUID],
        userId: UUID,
        in context: NSManagedObjectContext
    ) throws -> [Item] {
        guard !ids.isEmpty else {
            throw MaterializeError.noItemsFound
        }

        var itemsById: [UUID: Item] = [:]
        itemsById.reserveCapacity(ids.count)

        for itemId in ids {
            let request = NSFetchRequest<Item>(entityName: "Item")
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", itemId as CVarArg),
                NSPredicate(format: "userId == %@", userId.uuidString),
                NSPredicate(format: "isDraft != YES"),
                NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
            ])
            if let item = try context.fetch(request).first {
                itemsById[itemId] = item
            }
        }

        let orderedItems = ids.compactMap { itemsById[$0] }
        guard !orderedItems.isEmpty else {
            throw MaterializeError.noItemsFound
        }
        return orderedItems
    }

    private static func downloadProcessedImageData(from url: URL) async throws -> Data? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let image = UIImage(data: data),
              let processed = image.processForStorage() else {
            return nil
        }
        return processed
    }
}

struct OutfitRedressSuggestionContext: Equatable {
    let suggestionId: UUID
    let status: String
    let suggesterUserId: UUID?
    let suggesterUsername: String?
    let suggesterDisplayName: String?
    let suggesterAvatarUrl: String?
    let suggestedAt: Date?

    var isPending: Bool { status == "pending" }

    var submitterCaption: String {
        let username = suggesterUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !username.isEmpty { return username }
        let displayName = suggesterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        return "Someone"
    }
}

extension Outfit {
    var redressSubmitterCaption: String? {
        let username = redressSuggesterUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !username.isEmpty { return username }
        let displayName = redressSuggesterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        return nil
    }

    func persistRedressHistory(from context: OutfitRedressSuggestionContext) {
        _ = persistRedressHistoryIfNeeded(from: context)
    }

    /// Updates redress history fields only when values differ. Returns whether anything changed.
    @discardableResult
    func persistRedressHistoryIfNeeded(from context: OutfitRedressSuggestionContext) -> Bool {
        var changed = false
        if let suggestedAt = context.suggestedAt, redressSuggestedAt != suggestedAt {
            redressSuggestedAt = suggestedAt
            changed = true
        }
        if let userId = context.suggesterUserId, redressSuggesterUserId != userId {
            redressSuggesterUserId = userId
            changed = true
        }
        if let username = context.suggesterUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty,
           redressSuggesterUsername != username {
            redressSuggesterUsername = username
            changed = true
        }
        if let displayName = context.suggesterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty,
           redressSuggesterDisplayName != displayName {
            redressSuggesterDisplayName = displayName
            changed = true
        }
        if let avatarUrl = context.suggesterAvatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !avatarUrl.isEmpty,
           redressSuggesterAvatarUrl != avatarUrl {
            redressSuggesterAvatarUrl = avatarUrl
            changed = true
        }
        return changed
    }

    /// Persists suggester identity from a pending suggestion summary (includes avatar URL).
    @discardableResult
    func persistRedressSuggesterIfNeeded(from summary: VisibleWardrobeOutfit) -> Bool {
        var changed = false
        if redressSuggestedAt == nil {
            redressSuggestedAt = Date()
            changed = true
        }
        if let userId = summary.suggesterUserId, redressSuggesterUserId != userId {
            redressSuggesterUserId = userId
            changed = true
        }
        if let username = summary.suggesterUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty,
           redressSuggesterUsername != username {
            redressSuggesterUsername = username
            changed = true
        }
        if let displayName = summary.suggesterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty,
           redressSuggesterDisplayName != displayName {
            redressSuggesterDisplayName = displayName
            changed = true
        }
        if let avatarUrl = summary.suggesterAvatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !avatarUrl.isEmpty,
           redressSuggesterAvatarUrl != avatarUrl {
            redressSuggesterAvatarUrl = avatarUrl
            changed = true
        }
        return changed
    }
}

extension VisibleWardrobeOutfit {
    var redressSubmitterCaption: String? {
        guard isPendingSuggestion else { return nil }
        let username = suggesterUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !username.isEmpty { return username }
        let displayName = suggesterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        return nil
    }
}

struct OutfitSuggestionMaterializationRecord: Decodable {
    let id: UUID
    let recipientUserId: UUID
    let suggesterUserId: UUID
    let status: String
    let proposedName: String?
    let proposedNotes: String?
    let imageUrl: String?
    let createdAt: Date?
    let itemIds: [UUID]
    private let transformationJSON: [SavedOutfitItem]?

    enum CodingKeys: String, CodingKey {
        case id
        case recipientUserId = "recipient_user_id"
        case suggesterUserId = "suggester_user_id"
        case status
        case proposedName = "proposed_name"
        case proposedNotes = "proposed_notes"
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case itemIds = "item_ids"
        case transformationJSON = "transformation_json"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        recipientUserId = try container.decode(UUID.self, forKey: .recipientUserId)
        suggesterUserId = try container.decode(UUID.self, forKey: .suggesterUserId)
        status = try container.decode(String.self, forKey: .status)
        proposedName = try container.decodeIfPresent(String.self, forKey: .proposedName)
        proposedNotes = try container.decodeIfPresent(String.self, forKey: .proposedNotes)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        itemIds = try Self.decodeUUIDArray(from: container, forKey: .itemIds)
        transformationJSON = try Self.decodeTransformationJSON(from: container)
    }

    func transformationData(fallbackItemIds items: [Item]) -> Data? {
        let encoder = JSONEncoder()
        if let transformationJSON, !transformationJSON.isEmpty {
            return try? encoder.encode(transformationJSON)
        }

        let fallback = items.enumerated().compactMap { index, item -> SavedOutfitItem? in
            guard let itemID = item.id?.uuidString else { return nil }
            return SavedOutfitItem(
                itemID: itemID,
                positionX: 0,
                positionY: 0,
                scale: 1,
                rotation: 0,
                zIndex: index
            )
        }
        return try? encoder.encode(fallback)
    }

    private static func decodeUUIDArray(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [UUID] {
        if let uuids = try? container.decode([UUID].self, forKey: key) {
            return uuids
        }
        if let strings = try? container.decode([String].self, forKey: key) {
            return strings.compactMap(UUID.init(uuidString:))
        }
        return []
    }

    private static func decodeTransformationJSON(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [SavedOutfitItem]? {
        if let items = try? container.decode([SavedOutfitItem].self, forKey: .transformationJSON) {
            return items
        }
        if let jsonString = try? container.decode(String.self, forKey: .transformationJSON),
           let data = jsonString.data(using: .utf8),
           let items = try? JSONDecoder().decode([SavedOutfitItem].self, from: data) {
            return items
        }
        return nil
    }
}
