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
    let linkToEdit: Link? // ✅ renamed from editingLink
    let onLinkAdded: (Link) -> Void

    @State private var name: String = ""
    @State private var urlString: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Link name (e.g. Amazon)", text: $name)

                    TextField("URL (e.g. amazon.com/product)", text: $urlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Button(linkToEdit == nil ? "Save Link" : "Update Link") {
                    saveLink()
                }
                .disabled(!isValidInput)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .cornerRadius(12)
                .listRowBackground(isValidInput ? Color.blue : Color.gray)
            }
            .navigationTitle(linkToEdit == nil ? "Add Link" : "Edit Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let link = linkToEdit {
                    name = link.name ?? ""
                    urlString = link.url?.absoluteString ?? ""
                }
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
            // Update existing link
            editing.name = trimmedName
            editing.url = finalURL
            onLinkAdded(editing)
        } else {
            // Check for duplicates
            if let existing = existingLinks.first(where: {
                ($0.name ?? "").localizedCaseInsensitiveCompare(trimmedName) == .orderedSame &&
                $0.url == finalURL
            }) {
                onLinkAdded(existing)
                dismiss()
                return
            }

            // Create new Link
            let newLink = Link(context: viewContext)
            newLink.id = UUID()
            newLink.name = trimmedName
            newLink.url = finalURL
            newLink.item = item
            onLinkAdded(newLink)
        }

        dismiss()
    }
}


