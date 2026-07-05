//
//  OutfitAttributesSectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

// MARK: - OutfitAttributesSectionView
// Single source of truth for Outfit attributes (Name, Notes, etc.)
// Embedded in OutfitDetailView's List (mirrors AttributesSectionView + ItemDetailView).

import SwiftUI
import CoreData

struct OutfitAttributesSectionView: View {
    @ObservedObject var outfit: Outfit

    // One enum instead of many booleans
    @Binding var activeSheet: Sheet?
    /// Redress suggestions: suggester proposes name/notes only (not recipient category/tags).
    var redressSuggestionMode: Bool = false
    var isReadOnly: Bool = false

    var body: some View {
        Section {
            if showsNameRow {
                nameRow()
            }
            if showsCategoryRow {
                categoryRow()
            }
            if showsTagRow {
                tagRow()
            }
            if showsNotesRow {
                notesRow()
            }
        }
    }

    private var showsNameRow: Bool { true }

    private var showsCategoryRow: Bool {
        !isReadOnly && !redressSuggestionMode
    }

    private var showsTagRow: Bool {
        !isReadOnly && !redressSuggestionMode
    }

    private var showsNotesRow: Bool { true }

    private var hasName: Bool {
        !(outfit.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var hasCategory: Bool {
        !(outfit.category?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var hasTags: Bool {
        guard let tagSet = outfit.tags as? Set<Tag> else { return false }
        return !tagSet.isEmpty
    }

    private var hasNotes: Bool {
        !(outfit.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func hasReadOnlyVisibleContent(for outfit: Outfit) -> Bool {
        true
    }
}

// MARK: - Sheet enum
extension OutfitAttributesSectionView {
    enum Sheet: String, Identifiable {
        case name, category, tag, notes
        var id: String { rawValue }
    }
}

// MARK: - Rows
extension OutfitAttributesSectionView {
    // Name
    func nameRow() -> some View {
        Group {
            if isReadOnly {
                readOnlyAttributeRow(title: "Name", value: outfit.name)
            } else {
                Button { activeSheet = .name } label: {
                    editableAttributeLabel(title: "Name", value: outfit.name)
                }
            }
        }
    }

    // Category
    func categoryRow() -> some View {
        Group {
            if isReadOnly {
                readOnlyAttributeRow(title: "Category", value: outfit.category?.name)
            } else {
                Button { activeSheet = .category } label: {
                    editableAttributeLabel(title: "Category", value: outfit.category?.name)
                }
            }
        }
    }

    // Tags
    func tagRow() -> some View {
        Group {
            if isReadOnly {
                readOnlyAttributeRow(title: "Tags", value: tagNamesText)
            } else {
                Button { activeSheet = .tag } label: {
                    editableAttributeLabel(title: "Tags", value: tagNamesText, truncatePrefix: 20)
                }
            }
        }
    }

    // Notes
    func notesRow() -> some View {
        Group {
            if isReadOnly {
                readOnlyAttributeRow(title: "Notes", value: outfit.notes)
            } else {
                Button { activeSheet = .notes } label: {
                    editableAttributeLabel(title: "Notes", value: outfit.notes, truncatePrefix: 30)
                }
            }
        }
    }

    private var tagNamesText: String? {
        guard let tagSet = outfit.tags as? Set<Tag>, !tagSet.isEmpty else { return nil }
        return tagSet.compactMap { $0.name }.sorted().joined(separator: ", ")
    }

    private func editableAttributeLabel(title: String, value: String?, truncatePrefix: Int? = nil) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            if let value, !value.isEmpty {
                let display = truncatePrefix.map { String(value.prefix($0)) } ?? value
                Text(display)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .frame(width: 200, alignment: .trailing)
                    .truncationMode(.tail)
            }
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
    }

    private func readOnlyAttributeRow(title: String, value: String?) -> some View {
        let displayValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(displayValue)
                .foregroundColor(.gray)
                .multilineTextAlignment(.trailing)
                .lineLimit(title == "Notes" ? 3 : 1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Remote read-only attributes (public profile outfits)

struct ReadOnlyRemoteOutfitAttributesSection: View {
    let name: String?
    let notes: String?

    var body: some View {
        Section {
            readOnlyRow(title: "Name", value: name)
            readOnlyRow(title: "Notes", value: notes)
        }
    }

    static func hasVisibleContent(name: String?, notes: String?) -> Bool {
        true
    }

    private func readOnlyRow(title: String, value: String?) -> some View {
        let displayValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(displayValue)
                .foregroundColor(.gray)
                .multilineTextAlignment(.trailing)
                .lineLimit(title == "Notes" ? 3 : 1)
                .truncationMode(.tail)
        }
    }
}

struct ReadOnlyOutfitHistorySection: View {
    let label: String
    let date: Date?
    var caption: String? = nil
    @Binding var isExpanded: Bool

    var body: some View {
        if let date {
            Section {
                if isExpanded {
                    OutfitHistoryDateRow(label: label, date: date, caption: caption)
                        .transition(.opacity.combined(with: .slide))
                }
            } header: {
                HStack {
                    Text("HISTORY")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: isExpanded ? "minus" : "plus")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            }
            .listRowInsets(EdgeInsets(.zero))
            .listSectionSpacing(0)
            .padding(.horizontal)
        }
    }
}

struct OutfitHistoryDateRow: View {
    let label: String
    let date: Date
    var caption: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundColor(.gray)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.leading, 12)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Text(date, style: .date)
                .foregroundColor(.gray)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Sheet destination extension
extension OutfitAttributesSectionView.Sheet {
    @ViewBuilder
    func destination(for outfit: Outfit) -> some View {
        switch self {
        case .name:     SetOutfitNameView(outfit: outfit)
        case .category: SetOutfitCategoryView(outfit: outfit)
        case .tag:      SetOutfitTagView(outfit: outfit)
        case .notes:    SetOutfitNotesView(outfit: outfit)
        }
    }
}
