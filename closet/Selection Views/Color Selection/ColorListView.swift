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
    @Binding var selectedColorNames: Set<String>

    @FetchRequest(
        entity: AppColor.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AppColor.name, ascending: true)],
        predicate: NSPredicate(format: "isVisible == YES")
    ) private var visibleColors: FetchedResults<AppColor>

    var body: some View {
       // Section(header: SelectionHeader(title: "Select a Color")) {
            List {
                ForEach(visibleColors, id: \.self) { color in
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
        
      //  }
    }
}
