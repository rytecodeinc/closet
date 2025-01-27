//
//  UserWeightView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI

struct UserWeightView: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("userWeightKg") private var storedWeightKg: Double = 0
    @AppStorage("userWeightUnit") private var storedWeightUnit: String = ""
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "My Weight")
            
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
            saveWeight()
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
        // Load unit preference
        let savedUnit = storedWeightUnit.isEmpty ? nil : storedWeightUnit
        let newUnit: WeightUnit
        if let unit = savedUnit {
            newUnit = (unit == "kg") ? .kilograms : .pounds
        } else {
            newUnit = Locale.current.measurementSystem == .metric ? .kilograms : .pounds
        }
        
        selectedUnit = newUnit
        previousUnit = newUnit
        
        // Load weight value (stored in kg)
        guard storedWeightKg > 0, storedWeightKg.isFinite && !storedWeightKg.isNaN else {
            let currentMinLimit = self.minLimit
            let currentMaxLimit = self.maxLimit
            let defaultValue = (currentMinLimit + currentMaxLimit) / 2
            sliderWeightValue = defaultValue
            manualWeightInput = String(format: "%.1f", defaultValue)
            return
        }
        
        // Convert from stored kg to display unit
        let weightDisplay: Double
        if isKilograms {
            weightDisplay = storedWeightKg
        } else {
            weightDisplay = storedWeightKg * 2.20462
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
    
    private func saveWeight() {
        guard let manualWeight = Double(manualWeightInput),
              manualWeight.isFinite && !manualWeight.isNaN else {
            // Clear weight if invalid
            storedWeightKg = 0
            storedWeightUnit = ""
            return
        }
        
        let constrainedWeight = max(min(manualWeight, self.maxLimit), self.minLimit)
        let weightKg: Double
        
        if isKilograms {
            weightKg = constrainedWeight
        } else {
            weightKg = constrainedWeight * 0.453592
        }
        
        guard weightKg.isFinite && !weightKg.isNaN && weightKg > 0 else {
            return
        }
        
        // Save to UserDefaults via @AppStorage
        storedWeightKg = weightKg
        storedWeightUnit = isKilograms ? "kg" : "lbs"
        print("💾 Saved user weight: \(weightKg) kg (\(String(format: "%.1f", constrainedWeight)) \(isKilograms ? "kg" : "lbs"))")
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

