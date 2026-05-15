//
//  ColorListView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import Foundation
import SwiftUI
import CoreData

struct ColorListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedColorNames: Set<String>
    /// When set, only colors owned by or used by this user's items appear.
    var userId: String? = nil

    @State private var colors: [AppColor] = []

    var body: some View {
            List {
                if colors.isEmpty {
                    Text("Colors added to your closet will appear here.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(colors, id: \.objectID) { color in
                        let name = color.name ?? ""

                        HStack {
                            Circle()
                                .fill(colorFromName(name))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.gray, lineWidth: 1))

                            Text(name)
                                .foregroundColor(.black)

                            Spacer()

                            if selectedColorNames.contains(name) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedColorNames.contains(name) {
                                selectedColorNames.remove(name)
                            } else {
                                selectedColorNames.insert(name)
                            }
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle("Select Colors")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: fetchColors)
    }
    
    private func fetchColors() {
        let request = NSFetchRequest<AppColor>(entityName: "Color")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AppColor.name, ascending: true)]
        let visible = NSPredicate(format: "isVisible == YES")
        if let uid = userId {
            let owned = NSPredicate(format: "userId == %@", uid)
            let usedByUser = NSPredicate(
                format: "SUBQUERY(items, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                uid
            )
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                visible,
                NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
            ])
        } else {
            request.predicate = visible
        }
        do {
            let fetched = try viewContext.fetch(request)
            if let uid = userId {
                colors = dedupeNamedReferenceRows(fetched, preferredUserId: uid)
            } else {
                colors = fetched
            }
        } catch {
            print("❌ Failed to fetch colors: \(error.localizedDescription)")
            colors = []
        }
    }
}
