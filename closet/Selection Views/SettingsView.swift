//
//  SettingsView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        entity: NSEntityDescription.entity(forEntityName: "Color", in: PersistenceController.shared.container.viewContext)!,
        sortDescriptors: [NSSortDescriptor(keyPath: \AppColor.name, ascending: true)]
    ) var allColors: FetchedResults<AppColor>

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Color Visibility")) {
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
            }
            .navigationTitle("Settings")
            .onAppear {
                print("⚙️ SettingsView appeared. Total colors: \(allColors.count)")
                for color in allColors {
                    print("🟢 Color name: \(color.name ?? "nil"), isVisible: \(color.isVisible)")
                }
            }
        }
    }
}

