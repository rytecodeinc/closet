//
//  AddLinkFormView.swift
//  closet
//
//  Created by Dan Warner on 7/27/25.
//

import SwiftUI
import CoreData
import Foundation

struct AddLinkFormView: View {
    @Environment(\.dismiss) private var dismiss

    let item: Item
    let viewContext: NSManagedObjectContext
    let existingLinks: [Link]
    let linkToEdit: Link?
    let linkType: ItemLinkType
    let onLinkAdded: (Link) -> Void

    @State private var name: String = ""
    @State private var urlString: String = ""
    @State private var visibility: WardrobeVisibility = .private

    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(
                title: linkType.formTitle,
                leading: {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Links")
                        }
                        .foregroundColor(.blue)
                    }
                },
                trailing: { EmptyView() }
            )

            List {
                TextField("Link name (e.g. Amazon)", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("URL (e.g. amazon.com/product)", text: $urlString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Spacer()
                    ItemLinkVisibilityLabeledMenu(
                        visibility: visibility,
                        accessibilityPrefix: linkType.displayName
                    ) { visibility = $0 }
                }

                HStack {
                    Spacer(minLength: 0)
                    Button {
                        saveLink()
                    } label: {
                        Text(linkToEdit == nil ? "Add Link" : "Update Link")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(.cayenne.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValidInput)
                    .opacity(isValidInput ? 1 : 0.5)
                    Spacer(minLength: 0)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let link = linkToEdit {
                name = link.name ?? ""
                urlString = link.url?.absoluteString ?? ""
                visibility = link.itemLinkVisibility
            } else {
                visibility = item.linkSectionVisibility(for: linkType)
            }
        }
    }

    private var isValidInput: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let rawURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let preparedURLString = rawURL.lowercased().hasPrefix("http") ? rawURL : "https://\(rawURL)"

        guard
            let url = URL(string: preparedURLString),
            let host = url.host,
            url.scheme == "https" || url.scheme == "http",
            host.contains(".")
        else {
            return false
        }

        return true
    }

    private func saveLink() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var rawURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        if !rawURL.lowercased().hasPrefix("http") {
            rawURL = "https://\(rawURL)"
        }

        guard
            let finalURL = URL(string: rawURL),
            let host = finalURL.host,
            (finalURL.scheme == "http" || finalURL.scheme == "https"),
            host.contains(".")
        else {
            print("❌ Invalid URL")
            return
        }

        if let editing = linkToEdit {
            editing.name = trimmedName
            editing.url = finalURL
            editing.itemLinkType = linkType
            editing.itemLinkVisibility = visibility
            onLinkAdded(editing)
        } else {
            if let existing = existingLinks.first(where: {
                ($0.name ?? "").localizedCaseInsensitiveCompare(trimmedName) == .orderedSame &&
                $0.url == finalURL &&
                $0.itemLinkType == linkType
            }) {
                existing.itemLinkVisibility = visibility
                onLinkAdded(existing)
                dismiss()
                return
            }

            let newLink = Link(context: viewContext)
            newLink.id = UUID()
            newLink.name = trimmedName
            newLink.url = finalURL
            newLink.itemLinkType = linkType
            newLink.itemLinkVisibility = visibility
            newLink.item = item
            onLinkAdded(newLink)
        }

        dismiss()
    }
}
