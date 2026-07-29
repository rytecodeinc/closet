//
//  ProfileStyleTagsRow.swift
//  closet
//

import SwiftUI

/// Rounded, wrapping style chips centered beneath the profile header.
struct ProfileStyleTagsRow: View {
    let labels: [String]

    /// Soft pastels matching the profile header mockup.
    private static let chipColors: [Color] = [
        Color(red: 0.86, green: 0.80, blue: 0.88), // dusty rose / lavender
        Color(red: 0.82, green: 0.88, blue: 0.80), // sage
        Color(red: 0.94, green: 0.90, blue: 0.78), // cream
        Color(red: 0.86, green: 0.84, blue: 0.92),
        Color(red: 0.90, green: 0.86, blue: 0.80)
    ]

    var body: some View {
        ProfileStyleTagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(displayLabel(label))
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Self.chipColors[index % Self.chipColors.count],
                        in: Capsule()
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func displayLabel(_ label: String) -> String {
        let cleaned = label.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard !cleaned.isEmpty else { return "#" }
        return "#\(cleaned.lowercased())"
    }
}

private struct ProfileStyleTagFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = makeRows(subviews: subviews, maxWidth: maxWidth)
        let height = rows.enumerated().reduce(CGFloat.zero) { result, entry in
            result + entry.element.height + (entry.offset == 0 ? 0 : verticalSpacing)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX + max(0, (bounds.width - row.width) / 2)
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func makeRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        guard maxWidth.isFinite, maxWidth > 0 else { return [] }

        var rows: [Row] = []
        var row = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = row.indices.isEmpty
                ? size.width
                : row.width + horizontalSpacing + size.width

            if !row.indices.isEmpty, proposedWidth > maxWidth {
                rows.append(row)
                row = Row()
            }

            row.indices.append(index)
            row.width += (row.indices.count == 1 ? 0 : horizontalSpacing) + size.width
            row.height = max(row.height, size.height)
        }

        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}
