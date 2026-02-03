//
//  OutfitAttributesSectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

// MARK: - OutfitAttributesSectionView
// Single source of truth for Outfit attributes (Name, Notes, etc.)
// Works in OutfitDetailView with ScrollView/VStack layout

import SwiftUI
import CoreData

struct OutfitAttributesSectionView: View {
    @ObservedObject var outfit: Outfit

    // One enum instead of many booleans
    @Binding var activeSheet: Sheet?

    var body: some View {
        VStack(spacing: 2) {
            nameRow()
            
            Divider()
                .padding(.leading, 12)
            
            categoryRow()
            
            Divider()
                .padding(.leading, 12)
            
            notesRow()
        }
    }
}

// MARK: - Sheet enum
extension OutfitAttributesSectionView {
    enum Sheet: String, Identifiable {
        case name, category, notes
        var id: String { rawValue }
    }
}

// MARK: - Rows
extension OutfitAttributesSectionView {
    // Name
    func nameRow() -> some View {
        Button { activeSheet = .name } label: {
            HStack {
                Text("Name")
                    .foregroundColor(.primary)
                Spacer()
                if let name = outfit.name, !name.isEmpty {
                    Text(name)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .frame(width: 200, alignment: .trailing)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
    }
    
    // Category
    func categoryRow() -> some View {
        Button { activeSheet = .category } label: {
            HStack {
                Text("Category")
                    .foregroundColor(.primary)
                Spacer()
                if let category = outfit.category, !category.isEmpty {
                    Text(category)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.85)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
    }
    
    // Notes
    func notesRow() -> some View {
        Button { activeSheet = .notes } label: {
            HStack {
                Text("Notes")
                    .foregroundColor(.primary)
                Spacer()
                if let notes = outfit.notes, !notes.isEmpty {
                    Text(notes.prefix(30))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(8)
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
        case .notes:    SetOutfitNotesView(outfit: outfit)
        }
    }
}

