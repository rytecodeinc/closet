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

    @State private var colors: [AppColor] = []

    var body: some View {
            List {
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
            .listStyle(PlainListStyle())
            .navigationTitle("Select Colors")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: fetchColors)
    }
    
    private func fetchColors() {
        let request = NSFetchRequest<AppColor>(entityName: "Color")
        request.predicate = NSPredicate(format: "isVisible == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AppColor.name, ascending: true)]
        do {
            colors = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch colors: \(error.localizedDescription)")
            colors = []
        }
    }
}
