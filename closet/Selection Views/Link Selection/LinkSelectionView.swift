//
//  LinkSelectionView.swift
//  closet
//
//  Created by Dan Warner on 7/26/25.
//

import SwiftUI
import CoreData
import Foundation

struct LinkSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var links: [Link] = []
    @State private var showAddForm: Bool = false
    @State private var linkToEdit: Link? = nil

    var body: some View {
        SelectionHeader(title: "Purchase Links")

        VStack(spacing: 16) {
            Button(action: {
                showAddForm = true
                linkToEdit = nil // make sure it's clear you're adding
            }) {
                Label("Add Link", systemImage: "plus")
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
            }

            if links.isEmpty {
                Text("No links have been added.")
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                List {
                    ForEach(links, id: \.self) { link in
                        HStack {
                            Text(link.name ?? "")
                                .foregroundColor(.primary)
                            Spacer()
                            if let urlString = link.url?.absoluteString,
                               let url = URL(string: urlString) {
                                Button(action: {
                                    openURL(url)
                                }) {
                                    HStack(spacing: 4) {
                                        Text(url.host ?? urlString)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                            .frame(width: 150, alignment: .trailing)
                                        Image(systemName: "arrow.up.right")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .contentShape(Rectangle()) // makes full row tappable
                        .onTapGesture {
                            linkToEdit = link
                            showAddForm = true
                        }
                    }
                    .onDelete(perform: deleteLinks)
                }
                .listStyle(PlainListStyle())
            }
        }
        .sheet(isPresented: $showAddForm) {
            AddLinkFormView(
                item: item,
                viewContext: viewContext,
                existingLinks: links,
                linkToEdit: linkToEdit,
                onLinkAdded: { newLink in
                    if linkToEdit == nil {
                        item.addToLinks(newLink)
                    }
                    saveContext()
                    fetchLinks()
                }
            )
            .presentationDetents([.medium])
        }

        .onAppear(perform: fetchLinks)
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - URL Handling
    private func openURL(_ url: URL) {
        if UIApplication.shared.canOpenURL(url) {
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                UIApplication.shared.openURL(url)
            }
        }
    }

    // MARK: - Fetch Links
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

    // MARK: - Save Context
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to save context: \(error)")
        }
    }
    
    // MARK: - Delete Links
    private func deleteLinks(at offsets: IndexSet) {
        for index in offsets {
            let linkToDelete = links[index]
            viewContext.delete(linkToDelete)
        }
        saveContext()
        fetchLinks()
    }
}




