//
//  PackingChecklistDocumentModel.swift
//  closet
//
//  JSON document body for packing checklists (one doc per wardrobe + tab).
//

import Foundation

enum PackingChecklistDocKind: Int16, Codable {
    case items = 0
    case tasks = 1

    var segmentTag: String {
        switch self {
        case .items: return "Items"
        case .tasks: return "Tasks"
        }
    }

    static func fromSegment(_ tag: String) -> PackingChecklistDocKind {
        tag == "Tasks" ? .tasks : .items
    }
}

struct PackingChecklistDocumentBody: Codable, Equatable {
    var blocks: [PackingChecklistBlock]

    static var emptySeed: PackingChecklistDocumentBody {
        PackingChecklistDocumentBody(blocks: [
            .section(id: UUID(), title: "General"),
            .item(id: UUID(), text: "", checked: false)
        ])
    }
}

enum PackingChecklistBlock: Codable, Identifiable, Equatable {
    case section(id: UUID, title: String)
    case item(id: UUID, text: String, checked: Bool)

    var id: UUID {
        switch self {
        case .section(let id, _): return id
        case .item(let id, _, _): return id
        }
    }

    var isSection: Bool {
        if case .section = self { return true }
        return false
    }

    var isItem: Bool {
        if case .item = self { return true }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case type, id, title, text, checked
    }

    enum BlockType: String, Codable {
        case section
        case item
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(BlockType.self, forKey: .type)
        let id = try c.decode(UUID.self, forKey: .id)
        switch type {
        case .section:
            let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            self = .section(id: id, title: title)
        case .item:
            let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            let checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
            self = .item(id: id, text: text, checked: checked)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .section(let id, let title):
            try c.encode(BlockType.section, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(title, forKey: .title)
        case .item(let id, let text, let checked):
            try c.encode(BlockType.item, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
            try c.encode(checked, forKey: .checked)
        }
    }
}

enum PackingChecklistDocumentCodec {
    static func encode(_ body: PackingChecklistDocumentBody) -> Data? {
        try? JSONEncoder().encode(body)
    }

    static func decode(_ data: Data?) -> PackingChecklistDocumentBody? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(PackingChecklistDocumentBody.self, from: data)
    }
}
