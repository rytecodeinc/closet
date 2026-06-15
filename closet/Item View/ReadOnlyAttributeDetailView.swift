//
//  ReadOnlyAttributeDetailView.swift
//  closet
//

import SwiftUI
import CoreData

struct ReadOnlyAttributeDetailView: View {
    let sheet: AttributesSectionView.Sheet
    @ObservedObject var item: Item

    private let headerHeight: CGFloat = 56
    private let rowHeight: CGFloat = 44
    private let listPadding: CGFloat = 8

    private var usesListStyle: Bool {
        switch sheet {
        case .color, .season, .link, .tag:
            return true
        default:
            return false
        }
    }

    private var listRowCount: Int {
        switch sheet {
        case .color:
            return (item.colors as? Set<AppColor>)?.count ?? 0
        case .season:
            return (item.seasons as? Set<Season>)?.count ?? 0
        case .link:
            return (item.links as? Set<Link>)?.count ?? 0
        case .tag:
            return (item.tags as? Set<Tag>)?.count ?? 0
        default:
            return 0
        }
    }

    private var presentationHeight: CGFloat {
        if usesListStyle {
            return min(300, max(200, headerHeight + CGFloat(listRowCount) * rowHeight + listPadding))
        }
        return 200
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: sheet.readOnlyTitle(for: item))

            if usesListStyle {
                listContent
                    .listStyle(.plain)
            } else {
                ScrollView {
                    textValueContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .presentationDetents([.height(presentationHeight)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            switch sheet {
            case .color:
                if let colors = item.colors as? Set<AppColor>, !colors.isEmpty {
                    let sorted = colors.sorted { ($0.name ?? "") < ($1.name ?? "") }
                    ForEach(sorted, id: \.self) { appColor in
                        readOnlyCheckmarkRow {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(colorFromName(appColor.name ?? ""))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                                Text(appColor.name ?? "")
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }

            case .season:
                if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
                    let sorted = seasons.sorted { ($0.name ?? "") < ($1.name ?? "") }
                    ForEach(sorted, id: \.self) { season in
                        readOnlyCheckmarkRow {
                            Text(season.name ?? "")
                                .foregroundColor(.primary)
                        }
                    }
                }

            case .link:
                if let links = item.links as? Set<Link>, !links.isEmpty {
                    let sorted = links.sorted { ($0.name ?? "") < ($1.name ?? "") }
                    ForEach(sorted, id: \.self) { link in
                        readOnlyCheckmarkRow {
                            Text(link.name ?? "")
                                .foregroundColor(.primary)
                        }
                    }
                }

            case .tag:
                if let tags = item.tags as? Set<Tag>, !tags.isEmpty {
                    let sorted = tags.sorted { ($0.name ?? "") < ($1.name ?? "") }
                    ForEach(sorted, id: \.self) { tag in
                        readOnlyCheckmarkRow {
                            Text(tag.name ?? "")
                                .foregroundColor(.primary)
                        }
                    }
                }

            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var textValueContent: some View {
        switch sheet {
        case .name:
            detailText(item.name)
        case .category:
            detailText(AttributesSectionView.categoryDisplayText(for: item))
        case .brand:
            detailText(item.brand?.name)
        case .size:
            detailText(item.itemSize?.value)
        default:
            EmptyView()
        }
    }

    private func readOnlyCheckmarkRow<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        HStack {
            label()
            Spacer()
            Image(systemName: "checkmark")
                .foregroundColor(.blue)
        }
    }

    @ViewBuilder
    private func detailText(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            Text(text)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        }
    }
}

extension AttributesSectionView.Sheet {
    func readOnlyTitle(for item: Item) -> String {
        switch self {
        case .name: return "Name"
        case .category: return "Category"
        case .brand: return "Brand"
        case .size: return "Size"
        case .color: return "Colors"
        case .season: return "Seasons"
        case .link:
            let count = (item.links as? Set<Link>)?.count ?? 0
            return count <= 1 ? "Link" : "Links"
        case .tag: return "Tags"
        default: return rawValue.capitalized
        }
    }
}
