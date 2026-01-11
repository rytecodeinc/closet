//
//  SetWeatherView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI
import CoreData

struct SetWeatherView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedRanges: Set<Int> = [] // Store range indices (0-9, 10-19, etc.)
    @State private var manualMinInput: String = ""
    @State private var manualMaxInput: String = ""
    @State private var isCelsius: Bool = true
    
    // Temperature ranges for Celsius: -36 to 43 (groups of 10, max 43°C ≈ 110°F)
    private let celsiusRanges: [(min: Double, max: Double)] = [
        (-36, -27), (-26, -17), (-16, -7), (-6, 3), (4, 13),
        (14, 23), (24, 33), (34, 43)
    ]
    
    // Temperature ranges for Fahrenheit: -33 to 110 (groups of 10)
    private let fahrenheitRanges: [(min: Double, max: Double)] = [
        (-33, -24), (-23, -14), (-13, -4), (-3, 6), (7, 16), (17, 26),
        (27, 36), (37, 46), (47, 56), (57, 66), (67, 76), (77, 86),
        (87, 96), (97, 106), (107, 110)
    ]
    
    var currentRanges: [(min: Double, max: Double)] {
        isCelsius ? celsiusRanges : fahrenheitRanges
    }
    
    var temperatureSymbol: String {
        isCelsius ? "°C" : "°F"
    }
    
    var temperatureUnit: String {
        isCelsius ? "C" : "F"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "Set Weather Range")
            
            VStack(spacing: 16) {
                // Celsius/Fahrenheit Toggle
                HStack {
                    Text("Celsius")
                        .foregroundColor(isCelsius ? .primary : .secondary)
                    Toggle("", isOn: $isCelsius)
                        .labelsHidden()
                        .onChange(of: isCelsius) {
                            convertBetweenUnits()
                        }
                    Text("Fahrenheit")
                        .foregroundColor(!isCelsius ? .primary : .secondary)
                }
                .padding(.horizontal)
                .padding(.top)
                
                Divider()
                
                // Manual Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Manual Entry")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Min", text: $manualMinInput)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: manualMinInput) {
                                    updateRangesFromManualInput()
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Max", text: $manualMaxInput)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: manualMaxInput) {
                                    updateRangesFromManualInput()
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // Range Selection Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Ranges (Groups of 10)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(Array(currentRanges.enumerated()), id: \.offset) { index, range in
                                rangeButton(index: index, range: range)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxHeight: 300)
                
                Spacer()
            }
            
            // Save button
            Button("Save") {
                saveWeather()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            loadExistingWeather()
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Range Button
    private func rangeButton(index: Int, range: (min: Double, max: Double)) -> some View {
        Button(action: {
            toggleRange(index)
        }) {
            Text("\(Int(range.min))-\(Int(range.max))\(temperatureSymbol)")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedRanges.contains(index) ? Color.blue : Color(.systemGray5))
                .foregroundColor(selectedRanges.contains(index) ? .white : .primary)
                .cornerRadius(8)
        }
    }
    
    // MARK: - Toggle Range
    private func toggleRange(_ index: Int) {
        if selectedRanges.contains(index) {
            selectedRanges.remove(index)
        } else {
            selectedRanges.insert(index)
            // Automatically fill in gaps between selected ranges
            fillGapsInRanges()
        }
        updateManualInputFromRanges()
    }
    
    // MARK: - Fill Gaps
    private func fillGapsInRanges() {
        guard !selectedRanges.isEmpty else { return }
        let sorted = selectedRanges.sorted()
        let minIndex = sorted.first!
        let maxIndex = sorted.last!
        
        // Validate indices are within bounds
        guard minIndex >= 0 && maxIndex < currentRanges.count else { return }
        
        // Fill all ranges between min and max
        for index in minIndex...maxIndex {
            selectedRanges.insert(index)
        }
    }
    
    // MARK: - Update Manual Input from Ranges
    private func updateManualInputFromRanges() {
        guard !selectedRanges.isEmpty else {
            manualMinInput = ""
            manualMaxInput = ""
            return
        }
        
        // Filter out invalid indices and sort
        let validIndices = selectedRanges.filter { $0 >= 0 && $0 < currentRanges.count }
        guard !validIndices.isEmpty else {
            selectedRanges.removeAll()
            manualMinInput = ""
            manualMaxInput = ""
            return
        }
        
        let sorted = validIndices.sorted()
        let minIndex = sorted.first!
        let maxIndex = sorted.last!
        
        // Ensure indices are still valid
        guard minIndex >= 0 && minIndex < currentRanges.count,
              maxIndex >= 0 && maxIndex < currentRanges.count else {
            return
        }
        
        let minRange = currentRanges[minIndex]
        let maxRange = currentRanges[maxIndex]
        
        manualMinInput = String(Int(round(minRange.min)))
        manualMaxInput = String(Int(round(maxRange.max)))
        
        // Update selectedRanges to only include valid indices
        selectedRanges = Set(validIndices)
    }
    
    // MARK: - Update Ranges from Manual Input
    private func updateRangesFromManualInput() {
        guard let minValue = Double(manualMinInput),
              let maxValue = Double(manualMaxInput) else {
            // Invalid input, don't update ranges
            return
        }
        
        // Use the helper function to select ranges
        selectRangesForMinMax(min: minValue, max: maxValue)
        
        // Update manual input with constrained values if they changed
        // Get the constrained values by checking limits
        let maxLimit = isCelsius ? 43.0 : 110.0
        let minLimit = isCelsius ? -36.0 : -33.0
        
        let constrainedMin = Swift.max(minValue, minLimit)
        let constrainedMax = Swift.min(maxValue, maxLimit)
        
        // Update manual input if values were constrained
        if constrainedMin != minValue || constrainedMax != maxValue {
            manualMinInput = String(Int(round(constrainedMin)))
            manualMaxInput = String(Int(round(constrainedMax)))
            // Re-select ranges with constrained values
            selectRangesForMinMax(min: constrainedMin, max: constrainedMax)
        }
    }
    
    // MARK: - Convert Between Units
    private func convertBetweenUnits() {
        // Convert using manual input values instead of range indices to avoid index issues
        guard let minValue = Double(manualMinInput),
              let maxValue = Double(manualMaxInput),
              minValue < maxValue,
              (maxValue - minValue) >= 1.0 else {
            // If no valid manual input, clear selection
            selectedRanges.removeAll()
            return
        }
        
        // Convert the values (they're already in the OLD unit, isCelsius has already toggled)
        // So if isCelsius is NOW true, we were in Fahrenheit before
        let oldMin = minValue
        let oldMax = maxValue
        
        // Convert to new unit
        var newMin: Double
        var newMax: Double
        
        if isCelsius {
            // Converting from Fahrenheit to Celsius
            newMin = (oldMin - 32) * 5/9
            newMax = (oldMax - 32) * 5/9
        } else {
            // Converting from Celsius to Fahrenheit
            newMin = (oldMin * 9/5) + 32
            newMax = (oldMax * 9/5) + 32
        }
        
        // Round first to get integer values (this is what we display)
        newMin = round(newMin)
        newMax = round(newMax)
        
        // Apply constraints after rounding
        let maxLimit = isCelsius ? 43.0 : 110.0
        let minLimit = isCelsius ? -36.0 : -33.0
        
        let constrainedMin = max(newMin, minLimit)
        let constrainedMax = min(newMax, maxLimit)
        
        // Ensure min is still at least 1 less than max after constraints
        guard constrainedMin < constrainedMax, (constrainedMax - constrainedMin) >= 1.0 else {
            selectedRanges.removeAll()
            return
        }
        
        // Update manual input with converted and constrained values (already rounded)
        manualMinInput = String(Int(constrainedMin))
        manualMaxInput = String(Int(constrainedMax))
        
        // Find corresponding ranges in new unit based on converted values
        selectedRanges.removeAll()
        for (index, range) in currentRanges.enumerated() {
            if range.max >= constrainedMin && range.min <= constrainedMax {
                selectedRanges.insert(index)
            }
        }
    }
    
    // MARK: - Load Existing Weather
    private func loadExistingWeather() {
        // Set unit preference first
        if let unit = item.temperatureUnit {
            isCelsius = (unit == "C")
        } else {
            isCelsius = Locale.current.measurementSystem == .metric
        }
        
        // Load existing values (stored in Celsius)
        let minC = item.primitiveValue(forKey: "minTemperature") as? Double
        let maxC = item.primitiveValue(forKey: "maxTemperature") as? Double
        
        guard let minC = minC, let maxC = maxC else {
            return
        }
        
        // Convert to display unit if needed
        let minDisplay = isCelsius ? minC : (minC * 9/5) + 32
        let maxDisplay = isCelsius ? maxC : (maxC * 9/5) + 32
        
        // Round the display values
        let minRounded = round(minDisplay)
        let maxRounded = round(maxDisplay)
        
        // Set manual input
        manualMinInput = String(Int(minRounded))
        manualMaxInput = String(Int(maxRounded))
        
        // Select corresponding ranges using the rounded values directly
        selectRangesForMinMax(min: minRounded, max: maxRounded)
    }
    
    // MARK: - Select Ranges for Min/Max Values
    private func selectRangesForMinMax(min minValue: Double, max maxValue: Double) {
        // Validate: min must be at least 1 less than max
        guard minValue < maxValue, (maxValue - minValue) >= 1.0 else {
            return
        }
        
        // Constrain max to 110°F (43°C) and min to -33°F (-36°C)
        let maxLimit = isCelsius ? 43.0 : 110.0
        let minLimit = isCelsius ? -36.0 : -33.0
        
        let constrainedMin = Swift.max(minValue, minLimit)
        let constrainedMax = Swift.min(maxValue, maxLimit)
        
        // Ensure min is still at least 1 less than max after constraints
        guard constrainedMin < constrainedMax, (constrainedMax - constrainedMin) >= 1.0 else {
            return
        }
        
        // Find which ranges should be selected based on min/max
        selectedRanges.removeAll()
        for (index, range) in currentRanges.enumerated() {
            // Select range if it overlaps with the min-max range
            if range.max >= constrainedMin && range.min <= constrainedMax {
                selectedRanges.insert(index)
            }
        }
    }
    
    // MARK: - Save Weather
    private func saveWeather() {
        guard !selectedRanges.isEmpty else {
            // Clear weather data
            item.setPrimitiveValue(nil, forKey: "minTemperature")
            item.setPrimitiveValue(nil, forKey: "maxTemperature")
            item.temperatureUnit = nil
            
            if viewContext.parent == nil {
                try? viewContext.save()
            }
            dismiss()
            return
        }
        
        // Determine min and max values
        let minValue: Double
        let maxValue: Double
        
        // Constraints
        let maxLimit = isCelsius ? 43.0 : 110.0
        let minLimit = isCelsius ? -36.0 : -33.0
        
        // Use manual input if available and valid, otherwise use range boundaries
        if let manualMin = Double(manualMinInput),
           let manualMax = Double(manualMaxInput),
           manualMin < manualMax,
           (manualMax - manualMin) >= 1.0 {
            // Apply constraints
            let constrainedMin = max(manualMin, minLimit)
            let constrainedMax = min(manualMax, maxLimit)
            
            // Ensure min is still at least 1 less than max after constraints
            guard constrainedMin < constrainedMax, (constrainedMax - constrainedMin) >= 1.0 else {
                return
            }
            
            minValue = constrainedMin
            maxValue = constrainedMax
        } else {
            // Fallback to range boundaries
            let validIndices = selectedRanges.filter { $0 >= 0 && $0 < currentRanges.count }
            guard !validIndices.isEmpty else {
                return
            }
            let sorted = validIndices.sorted()
            let minIndex = sorted.first!
            let maxIndex = sorted.last!
            guard minIndex >= 0 && minIndex < currentRanges.count,
                  maxIndex >= 0 && maxIndex < currentRanges.count else {
                return
            }
            let minRange = currentRanges[minIndex]
            let maxRange = currentRanges[maxIndex]
            
            // Apply constraints to range boundaries
            let constrainedMin = max(minRange.min, minLimit)
            let constrainedMax = min(maxRange.max, maxLimit)
            
            // Ensure min is still at least 1 less than max after constraints
            guard constrainedMin < constrainedMax, (constrainedMax - constrainedMin) >= 1.0 else {
                return
            }
            
            minValue = constrainedMin
            maxValue = constrainedMax
        }
        
        // Convert to Celsius for storage
        let minC: Double
        let maxC: Double
        
        if isCelsius {
            minC = minValue
            maxC = maxValue
        } else {
            minC = (minValue - 32) * 5/9
            maxC = (maxValue - 32) * 5/9
        }
        
        // Save to Core Data
        item.setPrimitiveValue(minC, forKey: "minTemperature")
        item.setPrimitiveValue(maxC, forKey: "maxTemperature")
        item.temperatureUnit = temperatureUnit
        
        // Save context if parent context
        if viewContext.parent == nil {
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save weather: \(error.localizedDescription)")
            }
        }
        
        dismiss()
    }
}
