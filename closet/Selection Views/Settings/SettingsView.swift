//
//  SettingsView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI
import CoreData

struct SettingsView: View {
    @AppStorage("userWeightKg") private var storedWeightKg: Double = 0
    @AppStorage("userWeightUnit") private var storedWeightUnit: String = ""
    @State private var showWeightView = false
    
    private var displayWeightText: String? {
        guard storedWeightKg > 0 else { return nil }
        let unit = storedWeightUnit.isEmpty ? (Locale.current.measurementSystem == .metric ? "kg" : "lbs") : storedWeightUnit
        let displayWeight = unit == "kg" ? storedWeightKg : storedWeightKg * 2.20462
        return "\(String(format: "%.1f", displayWeight)) \(unit)"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Button {
                    showWeightView = true
                } label: {
                    HStack {
                        Text("Weight")
                            .foregroundColor(.primary)
                        Spacer()
                        if let weightText = displayWeightText {
                            Text(weightText)
                                .foregroundColor(.gray)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                }
                
                NavigationLink(destination: ColorVisibilityView()) {
                    Text("Colors")
                }
                NavigationLink(destination: SeasonVisibilityView()) {
                    Text("Seasons")
                }
                // Add more categories here later (Size, etc)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showWeightView) {
                UserWeightView()
            }
        }
    }
}


