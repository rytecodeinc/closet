//
//  ItemLinkType.swift
//  closet
//

import Foundation
import SwiftUI
import UIKit

enum ItemLinkRowMetrics {
    static let rowVerticalPadding: CGFloat = 11
    static let headerVerticalPadding: CGFloat = 2
    static let sectionBottomSpacing: CGFloat = 16
    static let detailNameLeadingInset: CGFloat = 16
    static let privacyIconLabelSpacing: CGFloat = 4
    static let hostFont: Font = .caption
}

struct ItemLinkVisibilityIcon: View {
    let visibility: WardrobeVisibility
    var font: Font = .body
    var accessibilityPrefix: String? = nil

    var body: some View {
        Image(systemName: visibility.iconName)
            .font(font)
            .fontWeight(.regular)
            .foregroundStyle(.secondary)
            .accessibilityLabel(
                accessibilityPrefix.map { "\($0) visibility, \(visibility.menuLabel)" }
                    ?? visibility.menuLabel
            )
    }
}

struct ItemLinkVisibilityIconMenu: View {
    let visibility: WardrobeVisibility
    var font: Font = .body
    let accessibilityPrefix: String
    let onSelect: (WardrobeVisibility) -> Void

    var body: some View {
        Menu {
            ForEach(WardrobeVisibility.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    Label(option.menuLabel, systemImage: option.iconName)
                }
            }
        } label: {
            ItemLinkVisibilityIcon(visibility: visibility, font: font)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityPrefix) visibility, \(visibility.menuLabel)")
    }
}

struct ItemLinkVisibilityLabeledMenu: View {
    let visibility: WardrobeVisibility
    let accessibilityPrefix: String
    let onSelect: (WardrobeVisibility) -> Void

    var body: some View {
        Menu {
            ForEach(WardrobeVisibility.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    Label(option.menuLabel, systemImage: option.iconName)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: visibility.iconName)
                Text(visibility.menuLabel)
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityPrefix) visibility, \(visibility.menuLabel)")
    }
}

struct ItemLinkSectionTitle: View {
    let type: ItemLinkType

    var body: some View {
        Text(type.sectionTitle)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

struct ItemLinkRowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 1 / max(UIScreen.main.scale, 1))
            .frame(maxWidth: .infinity)
    }
}

struct ItemLinkExternalArrow: View {
    var body: some View {
        Image(systemName: "arrow.up.right")
            .foregroundColor(.blue)
            .font(.caption)
    }
}

/// Name + host row; host is capped at half the row width.
struct ItemLinkNameHostRow<Leading: View, Accessory: View>: View {
    let name: String
    let host: String?
    var hostFont: Font = ItemLinkRowMetrics.hostFont
    var nameLeadingInset: CGFloat = 0
    var nameURL: URL? = nil
    var onRowTap: (() -> Void)? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var accessory: () -> Accessory

    init(
        name: String,
        host: String?,
        hostFont: Font = ItemLinkRowMetrics.hostFont,
        nameLeadingInset: CGFloat = 0,
        nameURL: URL? = nil,
        onRowTap: (() -> Void)? = nil,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.name = name
        self.host = host
        self.hostFont = hostFont
        self.nameLeadingInset = nameLeadingInset
        self.nameURL = nameURL
        self.onRowTap = onRowTap
        self.leading = leading
        self.accessory = accessory
    }

    var body: some View {
        if let onRowTap {
            Button(action: onRowTap) {
                rowContent
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            HStack(spacing: ItemLinkRowMetrics.privacyIconLabelSpacing) {
                leading()
                nameLabel
            }
            .padding(.leading, nameLeadingInset)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let host, !host.isEmpty {
                Text(host)
                    .font(hostFont)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            accessory()
        }
    }

    @ViewBuilder
    private var nameLabel: some View {
        if let nameURL, onRowTap == nil {
            SwiftUI.Link(destination: nameURL) {
                Text(name)
                    .foregroundColor(.blue)
                    .underline()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .tint(.blue)
        } else if nameURL != nil {
            Text(name)
                .foregroundColor(.blue)
                .underline()
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(name)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

extension ItemLinkNameHostRow where Leading == EmptyView {
    init(
        name: String,
        host: String?,
        hostFont: Font = ItemLinkRowMetrics.hostFont,
        nameLeadingInset: CGFloat = 0,
        nameURL: URL? = nil,
        onRowTap: (() -> Void)? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.init(
            name: name,
            host: host,
            hostFont: hostFont,
            nameLeadingInset: nameLeadingInset,
            nameURL: nameURL,
            onRowTap: onRowTap,
            leading: { EmptyView() },
            accessory: accessory
        )
    }
}

extension ItemLinkNameHostRow where Leading == EmptyView, Accessory == EmptyView {
    init(
        name: String,
        host: String?,
        hostFont: Font = ItemLinkRowMetrics.hostFont,
        nameLeadingInset: CGFloat = 0,
        nameURL: URL? = nil,
        onRowTap: (() -> Void)? = nil
    ) {
        self.init(
            name: name,
            host: host,
            hostFont: hostFont,
            nameLeadingInset: nameLeadingInset,
            nameURL: nameURL,
            onRowTap: onRowTap
        ) { EmptyView() }
    }
}

struct ItemLinkTypedSectionsView: View {
    let linksForType: (ItemLinkType) -> [Link]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ItemLinkType.allCases) { linkType in
                ItemLinkTypeSectionBlock(
                    linkType: linkType,
                    links: linksForType(linkType)
                )
            }
        }
    }
}

private struct ItemLinkTypeSectionBlock: View {
    let linkType: ItemLinkType
    let links: [Link]

    @Environment(\.openURL) private var openURL

    private var sectionVisibility: WardrobeVisibility {
        let unique = Set(links.map(\.itemLinkVisibility))
        if unique.count > 1 { return .public }
        if let only = unique.first { return only }
        return linkType.defaultVisibility
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ItemLinkRowMetrics.privacyIconLabelSpacing) {
                ItemLinkVisibilityIcon(
                    visibility: sectionVisibility,
                    font: .caption,
                    accessibilityPrefix: linkType.displayName
                )
                ItemLinkSectionTitle(type: linkType)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ItemLinkRowMetrics.headerVerticalPadding)

            ForEach(links, id: \.objectID) { link in
                VStack(spacing: 0) {
                    ItemLinkNameHostRow(
                        name: link.name ?? "",
                        host: link.url?.host,
                        nameLeadingInset: ItemLinkRowMetrics.detailNameLeadingInset,
                        onRowTap: {
                            guard let url = link.url else { return }
                            openURL(url)
                        },
                        leading: {
                            ItemLinkVisibilityIcon(
                                visibility: link.itemLinkVisibility,
                                font: .caption,
                                accessibilityPrefix: link.name ?? linkType.displayName
                            )
                        },
                        accessory: {
                            if link.url != nil {
                                ItemLinkExternalArrow()
                            }
                        }
                    )
                    .padding(.vertical, ItemLinkRowMetrics.rowVerticalPadding)

                    ItemLinkRowSeparator()
                }
            }
        }
        .padding(.bottom, ItemLinkRowMetrics.sectionBottomSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ItemLinkType: String, CaseIterable, Identifiable {
    case affiliate
    case purchase
    case reference

    var id: String { rawValue }

    var sectionTitle: String {
        displayName.uppercased()
    }

    var formTitle: String {
        "\(displayName) Link"
    }

    var displayName: String {
        switch self {
        case .affiliate: return "Affiliate"
        case .purchase: return "Purchase"
        case .reference: return "Reference"
        }
    }

    /// Untyped / unknown values bucket as Purchase.
    static func resolving(_ raw: String?) -> ItemLinkType {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ItemLinkType(rawValue: trimmed) ?? .purchase
    }

    var defaultVisibility: WardrobeVisibility {
        switch self {
        case .affiliate: return .public
        case .purchase, .reference: return .private
        }
    }
}

extension Link {
    var itemLinkType: ItemLinkType {
        get { ItemLinkType.resolving(type) }
        set { type = newValue.rawValue }
    }

    var itemLinkVisibility: WardrobeVisibility {
        get {
            WardrobeVisibility(rawValue: visibility ?? "") ?? itemLinkType.defaultVisibility
        }
        set {
            visibility = newValue.rawValue
        }
    }
}

extension Item {
    func linkSectionVisibility(for type: ItemLinkType) -> WardrobeVisibility {
        linkSectionVisibilityMap[type] ?? type.defaultVisibility
    }

    func displayedLinkSectionVisibility(for type: ItemLinkType, links: [Link]) -> WardrobeVisibility {
        let unique = Set(links.map(\.itemLinkVisibility))
        if unique.count > 1 { return .public }
        if let only = unique.first { return only }
        return linkSectionVisibility(for: type)
    }

    func setLinkSectionVisibility(_ visibility: WardrobeVisibility, for type: ItemLinkType) {
        var map = linkSectionVisibilityMap
        map[type] = visibility
        linkSectionVisibilityMap = map
    }

    private var linkSectionVisibilityMap: [ItemLinkType: WardrobeVisibility] {
        get {
            guard
                let data = linkSectionVisibility?.data(using: .utf8),
                let raw = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                return [:]
            }
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                guard
                    let type = ItemLinkType(rawValue: key),
                    let visibility = WardrobeVisibility(rawValue: value)
                else {
                    return nil
                }
                return (type, visibility)
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value.rawValue) })
            if let data = try? JSONEncoder().encode(raw) {
                linkSectionVisibility = String(data: data, encoding: .utf8)
            }
        }
    }
}
