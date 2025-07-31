//
//  TagListView.swift
//  closet
//
//  Created by Dan Warner on 7/29/25.
//


import SwiftUI
import CoreData

struct TagCloudView: View {
    let tags: [Tag]
    let onRemove: (Tag) -> Void

    private let screenWidth = UIScreen.main.bounds.size.width
    private let horizontalPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(computeRows(from: tags)) { row in
                HStack(spacing: 8) {
                    ForEach(row.tags) { tag in
                        tagView(for: tag)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func tagView(for tag: Tag) -> some View {
        HStack(spacing: 6) {
            Text(tag.name ?? "")
                .font(.subheadline)
                .foregroundColor(.white)

            Button(action: {
                onRemove(tag)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.blue))
        .fixedSize() // Prevents line-wrapping inside tag
    }

    // MARK: - Manual Layout Helpers

    struct TagRow: Identifiable {
        let id = UUID()
        var tags: [Tag] = []
    }

    private func computeRows(from tags: [Tag]) -> [TagRow] {
        var rows: [TagRow] = []
        var currentRow = TagRow()
        var currentWidth: CGFloat = 0

        let maxWidth = screenWidth - 2 * horizontalPadding

        for tag in tags {
            let tagWidth = tagSize(for: tag)

            if currentWidth + tagWidth + 8 > maxWidth {
                rows.append(currentRow)
                currentRow = TagRow(tags: [tag])
                currentWidth = tagWidth + 8
            } else {
                currentRow.tags.append(tag)
                currentWidth += tagWidth + 8
            }
        }

        if !currentRow.tags.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private func tagSize(for tag: Tag) -> CGFloat {
        let label = UILabel()
        label.text = (tag.name ?? "") + "   " // spacing for icon
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.sizeToFit()
        return label.frame.width + 24 // extra padding inside capsule
    }
}


