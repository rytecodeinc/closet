//
//  ColorVisibilityView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import CoreData
import Foundation

struct ColorVisibilityView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        entity: AppColor.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AppColor.name, ascending: true)]
    ) var allColors: FetchedResults<AppColor>

    var body: some View {
        List {
            ForEach(allColors, id: \.self) { color in
                Toggle(isOn: Binding(
                    get: { color.isVisible },
                    set: { newValue in
                        color.isVisible = newValue
                        try? viewContext.save()
                    })
                ) {
                    HStack {
                        Circle()
                            .fill(colorFromName(color.name ?? ""))
                            .frame(width: 24, height: 24)
                        Text(color.name ?? "")
                            .foregroundColor(.black)
                    }
                }
            }
        }
        .navigationTitle("Colors")
        .navigationBarTitleDisplayMode(.inline)
    }
}
