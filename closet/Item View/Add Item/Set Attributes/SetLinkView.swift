//
//  LinkSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetLinkView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var links: [Link] = []
    @State private var formRoute: LinkFormRoute?
    @State private var visibilityRevision = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SelectionPanelHeader(title: "Links")

                List {
                    ForEach(ItemLinkType.allCases) { linkType in
                        Section {
                            sectionHeader(linkType)
                                .deleteDisabled(true)
                                .listRowSeparator(.hidden)

                            ForEach(links(for: linkType), id: \.objectID) { link in
                                linkRow(link)
                            }
                            .onDelete { offsets in
                                deleteLinks(links(for: linkType), at: offsets)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .tint(.blue)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $formRoute) { route in
                AddLinkFormView(
                    item: item,
                    viewContext: viewContext,
                    existingLinks: links,
                    linkToEdit: route.linkToEdit(in: viewContext),
                    linkType: route.linkType,
                    onLinkAdded: { newLink in
                        if route.editingObjectID == nil {
                            item.addToLinks(newLink)
                        }

                        setUpdatedAt(item)

                        if viewContext.parent == nil {
                            do {
                                try viewContext.save()
                            } catch {
                                print("❌ Failed to save link: \(error.localizedDescription)")
                            }
                        }

                        fetchLinks()
                    }
                )
            }
        }
        .onAppear(perform: fetchLinks)
        .presentationDetents([.medium, .large])
    }

    private func sectionHeader(_ linkType: ItemLinkType) -> some View {
        let visibility = item.displayedLinkSectionVisibility(for: linkType, links: links(for: linkType))
        return HStack(spacing: 12) {
            HStack(spacing: ItemLinkRowMetrics.privacyIconLabelSpacing) {
                ItemLinkVisibilityIconMenu(
                    visibility: visibility,
                    font: .caption,
                    accessibilityPrefix: linkType.displayName
                ) { option in
                    updateSectionVisibility(option, for: linkType)
                }
                .id("\(linkType.rawValue)-\(visibility.rawValue)-\(visibilityRevision)")

                ItemLinkSectionTitle(type: linkType)
            }

            Spacer()

            Button {
                formRoute = .add(linkType)
            } label: {
                Image(systemName: "plus")
                    .font(.body)
                    .fontWeight(.regular)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(linkType.formTitle)")
        }
        .textCase(nil)
        .padding(.vertical, ItemLinkRowMetrics.headerVerticalPadding)
    }

    private func updateSectionVisibility(_ visibility: WardrobeVisibility, for linkType: ItemLinkType) {
        item.setLinkSectionVisibility(visibility, for: linkType)
        for link in links(for: linkType) {
            link.itemLinkVisibility = visibility
        }
        setUpdatedAt(item)
        visibilityRevision += 1

        if viewContext.parent == nil {
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save link section visibility: \(error.localizedDescription)")
            }
        }
    }

    private func linkRow(_ link: Link) -> some View {
        Button {
            editLink(link)
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: ItemLinkRowMetrics.privacyIconLabelSpacing) {
                    ItemLinkVisibilityIconMenu(
                        visibility: link.itemLinkVisibility,
                        font: .caption,
                        accessibilityPrefix: link.name ?? link.itemLinkType.displayName
                    ) { visibility in
                        updateRowVisibility(visibility, for: link)
                    }

                    Text(link.name ?? "")
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, ItemLinkRowMetrics.detailNameLeadingInset)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Text(link.url?.host ?? "")
                        .font(ItemLinkRowMetrics.hostFont)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    if let url = link.url {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .fontWeight(.regular)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(link.name ?? "link")")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func updateRowVisibility(_ visibility: WardrobeVisibility, for link: Link) {
        link.itemLinkVisibility = visibility
        setUpdatedAt(item)
        visibilityRevision += 1

        if viewContext.parent == nil {
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save link visibility: \(error.localizedDescription)")
            }
        }
    }

    private func editLink(_ link: Link) {
        formRoute = .edit(link)
    }

    private func links(for type: ItemLinkType) -> [Link] {
        links.filter { $0.itemLinkType == type }
    }

    private func fetchLinks() {
        let request: NSFetchRequest<Link> = Link.fetchRequest()
        request.predicate = NSPredicate(format: "item == %@", item)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Link.name, ascending: true)]
        do {
            links = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch links: \(error)")
            links = []
        }
    }

    private func deleteLinks(_ sectionLinks: [Link], at offsets: IndexSet) {
        for index in offsets {
            viewContext.delete(sectionLinks[index])
        }

        setUpdatedAt(item)

        if viewContext.parent == nil {
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save link deletion: \(error.localizedDescription)")
            }
        }

        fetchLinks()
    }
}

private struct LinkFormRoute: Identifiable, Hashable {
    let id: UUID
    let linkType: ItemLinkType
    let editingObjectID: NSManagedObjectID?

    static func add(_ type: ItemLinkType) -> LinkFormRoute {
        LinkFormRoute(id: UUID(), linkType: type, editingObjectID: nil)
    }

    static func edit(_ link: Link) -> LinkFormRoute {
        LinkFormRoute(id: UUID(), linkType: link.itemLinkType, editingObjectID: link.objectID)
    }

    func linkToEdit(in context: NSManagedObjectContext) -> Link? {
        guard let editingObjectID else { return nil }
        return context.object(with: editingObjectID) as? Link
    }
}
