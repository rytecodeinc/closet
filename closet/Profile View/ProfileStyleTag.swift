//
//  ProfileStyleTag.swift
//  closet
//

import Foundation

/// Fixed catalog of profile style tags (stored as raw values in Core Data / Supabase).
enum ProfileStyleTag: String, CaseIterable, Codable, Hashable, Identifiable {
    case minimalist = "Minimalist"
    case maximalist = "Maximalist"
    case streetwear = "Streetwear"
    case officewear = "Officewear"
    case vintage = "Vintage"
    case athleisure = "Athleisure"
    case maternity = "Maternity"
    case resortwear = "Resortwear"
    case modest = "Modest"
    case romantic = "Romantic"

    var id: String { rawValue }

    static let maxSelectionCount = 3

    /// Tags in display order, omitting any unknown raw strings.
    static func ordered(from rawValues: [String]) -> [ProfileStyleTag] {
        let selected = Set(rawValues.compactMap(ProfileStyleTag.init(rawValue:)))
        return allCases.filter { selected.contains($0) }
    }
}
