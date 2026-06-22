//
//  TagCloudView.swift
//  closet
//
//  Created by Dan Warner on 7/29/25.
//

import SwiftUI
import CoreData

struct TagCloudView: View {
    let tags: [Tag]
    let removeConfirmationMessage: (Tag) -> String
    let onRemove: (Tag) -> Void

    @State private var tagPendingRemoval: Tag?

    private static let chipFontSize: CGFloat = 15

    init(
        tags: [Tag],
        removeConfirmationMessage: @escaping (Tag) -> String = { tag in
            "Remove \"\(tag.name ?? "this tag")\"?"
        },
        onRemove: @escaping (Tag) -> Void
    ) {
        self.tags = tags
        self.removeConfirmationMessage = removeConfirmationMessage
        self.onRemove = onRemove
    }

    private var sortedTags: [Tag] {
        tags.sorted {
            ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
        }
    }

    var body: some View {
        TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 10) {
            ForEach(sortedTags, id: \.objectID) { tag in
                tagChip(for: tag)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Remove Tag", isPresented: removalAlertIsPresented) {
            Button("Remove", role: .destructive) {
                if let tag = tagPendingRemoval {
                    onRemove(tag)
                }
                tagPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                tagPendingRemoval = nil
            }
        } message: {
            if let tag = tagPendingRemoval {
                Text(removeConfirmationMessage(tag))
            }
        }
    }

    private var removalAlertIsPresented: Binding<Bool> {
        Binding(
            get: { tagPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    tagPendingRemoval = nil
                }
            }
        )
    }

    private func tagChip(for tag: Tag) -> some View {
        HStack(spacing: 4) {
            Text(tag.name ?? "")
                .font(.system(size: Self.chipFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button {
                tagPendingRemoval = tag
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .accessibilityLabel("Remove \(tag.name ?? "tag")")
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .tagChipBackground()
    }
}

private enum TagChipMetrics {
    static let cornerRadius: CGFloat = 8
}

private extension View {
    func tagChipBackground() -> some View {
        background {
            RoundedRectangle(cornerRadius: TagChipMetrics.cornerRadius, style: .continuous)
                .fill(TagChipStyle.background)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TagChipMetrics.cornerRadius, style: .continuous)
                .strokeBorder(TagChipStyle.border, lineWidth: 0.5)
        }
    }
}

// MARK: - Notes-style chip colors

private enum TagChipStyle {
    static var background: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.28, green: 0.26, blue: 0.20, alpha: 1)
                : UIColor(red: 0.98, green: 0.95, blue: 0.82, alpha: 1)
        })
    }

    static var border: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.08)
                : UIColor(red: 0.85, green: 0.80, blue: 0.62, alpha: 0.6)
        })
    }
}

// MARK: - Flow layout

private struct TagFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        guard maxWidth.isFinite, maxWidth > 0 else {
            return .zero
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }
    }
}
