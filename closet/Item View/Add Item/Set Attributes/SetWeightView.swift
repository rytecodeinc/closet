//
//  SetWeightView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI
import CoreData

enum WeightUnit: String, CaseIterable {
    case pounds = "lbs"
    case kilograms = "kg"
    
    var isKilograms: Bool {
        self == .kilograms
    }
}

struct SetWeightView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var manualWeightInput: String = ""
    @State private var selectedUnit: WeightUnit = Locale.current.measurementSystem == .metric ? .kilograms : .pounds
    @State private var sliderWeightValue: Double = 150.0
    @State private var isLoading: Bool = true
    @State private var previousUnit: WeightUnit? = nil
    
    var isKilograms: Bool {
        selectedUnit.isKilograms
    }
    
    var minLimit: Double {
        isKilograms ? 35.0 : 80.0
    }
    
    var maxLimit: Double {
        isKilograms ? 180.0 : 400.0
    }
    
    var weightSymbol: String {
        isKilograms ? "kg" : "lbs"
    }
    
    var weightUnitForStorage: String {
        isKilograms ? "kg" : "lbs"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "Set Weight")
            
            Picker("Weight Unit", selection: $selectedUnit) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom)
            .background(Color(UIColor.secondarySystemBackground))
            .onChange(of: selectedUnit) { newUnit in
                if !isLoading, let previous = previousUnit, previous != newUnit {
                    convertBetweenUnits()
                }
                previousUnit = newUnit
            }
            
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        WeightSlider(
                            value: $sliderWeightValue,
                            bounds: minLimit...maxLimit
                        )
                        .padding(.horizontal, 4)
                        .onChange(of: sliderWeightValue) {
                            updateWeightInputFromSlider()
                        }
                        
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Weight", text: $manualWeightInput)
                                    .keyboardType(.numbersAndPunctuation)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: manualWeightInput) {
                                        validateWeightInput()
                                    }
                                    .multilineTextAlignment(.center)
                                Text("Weight (\(weightSymbol))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .frame(maxWidth: 150)
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                Spacer()
            }
        }
        .onAppear {
            isLoading = true
            previousUnit = selectedUnit
            loadExistingWeight()
            previousUnit = selectedUnit
            isLoading = false
        }
        .onDisappear {
            applyWeightToItem()
        }
        .presentationDetents([.medium])
    }
    
    private func convertBetweenUnits() {
        guard let weightValue = Double(manualWeightInput),
              weightValue.isFinite && !weightValue.isNaN else {
            let currentMinLimit = self.minLimit
            let currentMaxLimit = self.maxLimit
            let defaultValue = (currentMinLimit + currentMaxLimit) / 2
            manualWeightInput = String(format: "%.1f", defaultValue)
            sliderWeightValue = defaultValue
            return
        }
        
        let oldWeight = weightValue
        var newWeight: Double
        
        if isKilograms {
            newWeight = oldWeight * 0.453592
        } else {
            newWeight = oldWeight / 0.453592
        }
        
        newWeight = round(newWeight * 10) / 10
        let constrainedWeight = max(min(newWeight, self.maxLimit), self.minLimit)
        manualWeightInput = String(format: "%.1f", constrainedWeight)
        sliderWeightValue = constrainedWeight
    }
    
    private func loadExistingWeight() {
        let savedUnit = item.primitiveValue(forKey: "weightUnit") as? String
        let newUnit: WeightUnit
        if let unit = savedUnit {
            newUnit = (unit == "kg") ? .kilograms : .pounds
        } else {
            newUnit = Locale.current.measurementSystem == .metric ? .kilograms : .pounds
        }
        
        selectedUnit = newUnit
        previousUnit = newUnit
        
        let rawWeightKg = item.primitiveValue(forKey: "weight") as? Double
        
        guard let weightKg = rawWeightKg,
              weightKg.isFinite && !weightKg.isNaN else {
            let currentMinLimit = self.minLimit
            let currentMaxLimit = self.maxLimit
            let defaultValue = (currentMinLimit + currentMaxLimit) / 2
            sliderWeightValue = defaultValue
            manualWeightInput = String(format: "%.1f", defaultValue)
            return
        }
        
        let weightDisplay: Double
        if isKilograms {
            weightDisplay = weightKg
        } else {
            weightDisplay = weightKg * 2.20462
        }
        
        guard weightDisplay.isFinite && !weightDisplay.isNaN else {
            let currentMinLimit = self.minLimit
            let currentMaxLimit = self.maxLimit
            let defaultValue = (currentMinLimit + currentMaxLimit) / 2
            sliderWeightValue = defaultValue
            manualWeightInput = String(format: "%.1f", defaultValue)
            return
        }
        
        var weightRounded = round(weightDisplay * 10) / 10
        let currentMinLimit = self.minLimit
        let currentMaxLimit = self.maxLimit
        
        if weightRounded < currentMinLimit {
            weightRounded = currentMinLimit
        }
        if weightRounded > currentMaxLimit {
            weightRounded = currentMaxLimit
        }
        
        manualWeightInput = String(format: "%.1f", weightRounded)
        sliderWeightValue = weightRounded
    }
    
    private func applyWeightToItem() {
        guard let manualWeight = Double(manualWeightInput),
              manualWeight.isFinite && !manualWeight.isNaN else {
            // Clear weight data if input is invalid
            // First ensure the values are accessed (not faults)
            _ = item.primitiveValue(forKey: "weight")
            _ = item.primitiveValue(forKey: "weightUnit")
            
            // Use setValue to properly notify Core Data of changes
            item.setValue(nil, forKey: "weight")
            item.setValue(nil, forKey: "weightUnit")
            
            // Mark item as changed to trigger UI refresh
            item.objectWillChange.send()
            
            // Process pending changes
            viewContext.processPendingChanges()
            
            // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
            // If viewContext has a parent, we're in a child context and shouldn't save
            if viewContext.parent == nil {
                // We're in a parent context (ItemDetailView), save immediately
                do {
                    try viewContext.save()
                    print("✅ Cleared weight successfully")
                } catch {
                    print("❌ Failed to clear weight: \(error.localizedDescription)")
                }
            }
            // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
            return
        }
        
        let constrainedWeight = max(min(manualWeight, self.maxLimit), self.minLimit)
        let weightKg: Double
        
        if isKilograms {
            weightKg = constrainedWeight
        } else {
            weightKg = constrainedWeight * 0.453592
        }
        
        guard weightKg.isFinite && !weightKg.isNaN else {
            print("❌ Invalid weight value to save: weightKg=\(weightKg)")
            return
        }
        
        // Save to Core Data - use setValue to properly trigger change notifications
        // First ensure the values are accessed (not faults)
        _ = item.primitiveValue(forKey: "weight")
        _ = item.primitiveValue(forKey: "weightUnit")
        
        // Now set the values using setValue which properly notifies Core Data
        item.setValue(weightKg, forKey: "weight")
        item.setValue(weightUnitForStorage, forKey: "weightUnit")
        
        // Debug: Print what we're saving
        print("💾 Saving weight: weightKg=\(weightKg), unit=\(weightUnitForStorage), displayWeight=\(String(format: "%.1f", constrainedWeight))")
        
        // Mark item as changed to trigger UI refresh
        item.objectWillChange.send()
        
        // Process pending changes to ensure Core Data tracks the changes
        viewContext.processPendingChanges()
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        // If viewContext has a parent, we're in a child context and shouldn't save
        if viewContext.parent == nil {
            // We're in a parent context (ItemDetailView), save immediately
            do {
                // Ensure we have changes to save
                guard viewContext.hasChanges else {
                    print("⚠️ No changes to save in context")
                    return
                }
                
                try viewContext.save()
                
                // Verify the save by reading back the value
                viewContext.refresh(item, mergeChanges: false)
                if let savedWeight = item.primitiveValue(forKey: "weight") as? Double,
                   let savedUnit = item.primitiveValue(forKey: "weightUnit") as? String {
                    print("✅ Weight saved successfully to persistent store: \(savedWeight) kg, unit: \(savedUnit)")
                } else {
                    print("⚠️ Warning: Weight save may have failed - value not found after save")
                }
            } catch {
                print("❌ Failed to save weight: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("❌ Error details: \(nsError.userInfo)")
                }
            }
        } else {
            // We're in a child context (ItemAddView), changes will be saved when parent saves
            print("✅ Weight set in child context (will be saved with item)")
        }
    }
    
    private func validateWeightInput() {
        guard let value = Double(manualWeightInput),
              value.isFinite,
              !value.isNaN else {
            manualWeightInput = String(format: "%.1f", sliderWeightValue)
            return
        }
        
        let validatedValue = min(max(self.minLimit, value), self.maxLimit)
        sliderWeightValue = validatedValue
        manualWeightInput = String(format: "%.1f", validatedValue)
    }
    
    private func updateWeightInputFromSlider() {
        manualWeightInput = String(format: "%.1f", sliderWeightValue)
    }
}

struct WeightSlider: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.gray.opacity(0.3))
                    .frame(height: 4)
                Capsule()
                    .fill(.blue)
                    .frame(width: thumbX(value, width), height: 4)
                Thumb(x: thumbX(value, width))
                    .gesture(dragGesture(width: width))
            }
        }
        .frame(height: 32)
    }
    
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                let percent = min(max(0, gesture.location.x / width), 1)
                let newValue = bounds.lowerBound + percent * (bounds.upperBound - bounds.lowerBound)
                value = newValue
            }
    }
    
    private func thumbX(_ value: Double, _ width: CGFloat) -> CGFloat {
        CGFloat((value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * width
    }
}
