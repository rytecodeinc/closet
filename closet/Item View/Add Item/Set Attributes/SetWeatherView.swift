//
//  SetWeatherView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI
import CoreData

enum TemperatureUnit: String, CaseIterable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"
    
    var isCelsius: Bool {
        self == .celsius
    }
}

struct SetWeatherView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var manualMinInput: String = ""
    @State private var manualMaxInput: String = ""
    @State private var selectedUnit: TemperatureUnit = Locale.current.measurementSystem == .metric ? .celsius : .fahrenheit
    @State private var sliderMinValue: Double = -33.0  // Will be updated in onAppear
    @State private var sliderMaxValue: Double = 110.0  // Will be updated in onAppear
    @State private var isLoading: Bool = true  // Prevents conversion during initial load
    @State private var previousUnit: TemperatureUnit? = nil  // Track previous unit to detect user changes
    
    var isCelsius: Bool {
        selectedUnit.isCelsius
    }
    
    var minLimit: Double {
        isCelsius ? -36.0 : -33.0
    }
    
    var maxLimit: Double {
        isCelsius ? 43.0 : 110.0
    }
    
    var temperatureSymbol: String {
        isCelsius ? "°C" : "°F"
    }
    
    var temperatureUnit: String {
        isCelsius ? "C" : "F"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: "Set Weather") {
                Picker("Temperature Unit", selection: $selectedUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedUnit) { newUnit in
                    if !isLoading, let previous = previousUnit, previous != newUnit {
                        convertBetweenUnits()
                    }
                    previousUnit = newUnit
                }
            }

            VStack(spacing: 6) {
                // Temperature Range Section
                VStack(alignment: .leading, spacing: 12) {
                    // Range Slider
                    VStack(spacing: 0) {
                        RangeSlider(
                            minValue: $sliderMinValue,
                            maxValue: $sliderMaxValue,
                            bounds: minLimit...maxLimit
                        )
                        .padding(.horizontal, 4)
                        .onChange(of: sliderMinValue) {
                            updateMinInputFromSlider()
                        }
                        .onChange(of: sliderMaxValue) {
                            updateMaxInputFromSlider()
                        }
                        
                        // Min and Max Input Fields
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Min", text: $manualMinInput)
                                    .keyboardType(.numbersAndPunctuation)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: manualMinInput) {
                                        validateMinInput()
                                    }
                                Text("Min \(temperatureSymbol)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: 100)
                            
                            Spacer()
                            
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Max", text: $manualMaxInput)
                                    .keyboardType(.numbersAndPunctuation)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: manualMaxInput) {
                                        validateMaxInput()
                                    }
                                    .multilineTextAlignment(.trailing)
                                Text("Max \(temperatureSymbol)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .frame(maxWidth: 100)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                Spacer()
                
                // Save Button
                HStack {
                    Spacer()
                    Button("Save") {
                        saveWeather()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    Spacer()
                }
                .padding(.bottom)
            }
        }
        .onAppear {
            isLoading = true
            previousUnit = selectedUnit  // Set initial previous value
            loadExistingWeather()
            // Set previous value to the loaded value AFTER loading
            previousUnit = selectedUnit
            isLoading = false  // After loading, allow conversion on toggle
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Convert Between Units
    private func convertBetweenUnits() {
        // CRITICAL: Read values from INPUT fields (current display values)
        guard let minValue = Double(manualMinInput),
              let maxValue = Double(manualMaxInput),
              minValue.isFinite && maxValue.isFinite,
              !minValue.isNaN && !maxValue.isNaN,
              minValue < maxValue,
              (maxValue - minValue) >= 1.0 else {
            // If inputs are invalid, initialize to bounds
            let currentMinLimit = self.minLimit
            let currentMaxLimit = self.maxLimit
            manualMinInput = String(Int(currentMinLimit))
            manualMaxInput = String(Int(currentMaxLimit))
            sliderMinValue = currentMinLimit
            sliderMaxValue = currentMaxLimit
            return
        }
        
        // These values are in the OLD unit (isCelsius has already toggled)
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
        
        // Round first to get integer values
        newMin = round(newMin)
        newMax = round(newMax)
        
        // Apply constraints after rounding
        let constrainedMin = max(newMin, self.minLimit)
        let constrainedMax = min(newMax, self.maxLimit)
        
        // Ensure min is still at least 1 less than max after constraints
        guard constrainedMin < constrainedMax, (constrainedMax - constrainedMin) >= 1.0 else {
            // If constraint broke the relationship, use bounds
            let currentMinLimit = self.minLimit
            let currentMaxLimit = self.maxLimit
            manualMinInput = String(Int(currentMinLimit))
            manualMaxInput = String(Int(currentMaxLimit))
            sliderMinValue = currentMinLimit
            sliderMaxValue = currentMaxLimit
            return
        }
        
        // Update BOTH inputs AND slider values with converted values
        manualMinInput = String(Int(constrainedMin))
        manualMaxInput = String(Int(constrainedMax))
        sliderMinValue = constrainedMin
        sliderMaxValue = constrainedMax
        
        print("🔄 Unit converted: \(oldMin) to \(constrainedMin), \(oldMax) to \(constrainedMax) (\(isCelsius ? "°C" : "°F"))")
    }
    
    // MARK: - Load Existing Weather
    private func loadExistingWeather() {
        // STEP 1: Set unit preference first (CRITICAL: do this before loading/converting values)
        let savedUnit = item.primitiveValue(forKey: "temperatureUnit") as? String
        let newUnit: TemperatureUnit
        if let unit = savedUnit {
            newUnit = (unit == "C") ? .celsius : .fahrenheit
        } else {
            newUnit = Locale.current.measurementSystem == .metric ? .celsius : .fahrenheit
        }
        
        // Set both selectedUnit and previousUnit together to prevent onChange from triggering
        selectedUnit = newUnit
        previousUnit = newUnit  // Set immediately to prevent conversion trigger
        
        // STEP 2: Load existing values (stored in Celsius in Core Data)
        let rawMinC = item.primitiveValue(forKey: "minTemperature") as? Double
        let rawMaxC = item.primitiveValue(forKey: "maxTemperature") as? Double
        
        // Debug: Print what we're loading
        if let minC = rawMinC, let maxC = rawMaxC {
            print("📖 Loading weather: minC=\(minC), maxC=\(maxC), savedUnit=\(savedUnit ?? "nil"), isCelsius=\(isCelsius)")
        }
        
        guard let minC = rawMinC,
              let maxC = rawMaxC,
              minC.isFinite && maxC.isFinite,
              !minC.isNaN && !maxC.isNaN else {
            // No existing data - initialize to bounds for current unit
            let currentMinLimit = self.minLimit
            let currentMaxLimit = self.maxLimit
            sliderMinValue = currentMinLimit
            sliderMaxValue = currentMaxLimit
            manualMinInput = String(Int(currentMinLimit))
            manualMaxInput = String(Int(currentMaxLimit))
            print("📖 No saved weather, initializing to bounds: \(Int(currentMinLimit)) to \(Int(currentMaxLimit))")
            return
        }
        
        // STEP 3: Convert from stored Celsius to display unit
        // Values are ALWAYS stored in Celsius, so we convert based on isCelsius
        let minDisplay: Double
        let maxDisplay: Double
        
        if isCelsius {
            // Displaying in Celsius - use values directly
            minDisplay = minC
            maxDisplay = maxC
        } else {
            // Displaying in Fahrenheit - convert from Celsius
            minDisplay = (minC * 9/5) + 32
            maxDisplay = (maxC * 9/5) + 32
        }
        
        print("📖 Converted: minDisplay=\(minDisplay), maxDisplay=\(maxDisplay), isCelsius=\(isCelsius)")
        
        // STEP 4: Validate converted values
        guard minDisplay.isFinite && maxDisplay.isFinite,
              !minDisplay.isNaN && !maxDisplay.isNaN else {
            print("❌ Conversion failed, using bounds")
            let currentMinLimit = self.minLimit
            let currentMaxLimit = self.maxLimit
            sliderMinValue = currentMinLimit
            sliderMaxValue = currentMaxLimit
            manualMinInput = String(Int(currentMinLimit))
            manualMaxInput = String(Int(currentMaxLimit))
            return
        }
        
        // STEP 5: Round to integers for display
        var minRounded = round(minDisplay)
        var maxRounded = round(maxDisplay)
        
        // STEP 6: Ensure values are within bounds for the current unit
        let currentMinLimit = self.minLimit
        let currentMaxLimit = self.maxLimit
        
        // Only constrain if values are actually out of bounds
        if minRounded < currentMinLimit {
            print("⚠️ minRounded (\(minRounded)) below minLimit (\(currentMinLimit)), constraining")
            minRounded = currentMinLimit
        }
        if maxRounded > currentMaxLimit {
            print("⚠️ maxRounded (\(maxRounded)) above maxLimit (\(currentMaxLimit)), constraining")
            maxRounded = currentMaxLimit
        }
        
        // STEP 7: Ensure min < max after constraint
        guard minRounded < maxRounded else {
            print("❌ After constraint, min >= max (\(minRounded) >= \(maxRounded)), using bounds")
            let defaultMin = currentMinLimit
            let defaultMax = currentMaxLimit
            sliderMinValue = defaultMin
            sliderMaxValue = defaultMax
            manualMinInput = String(Int(defaultMin))
            manualMaxInput = String(Int(defaultMax))
            return
        }
        
        // STEP 8: Update UI with loaded values
        manualMinInput = String(Int(minRounded))
        manualMaxInput = String(Int(maxRounded))
        sliderMinValue = minRounded
        sliderMaxValue = maxRounded
        
        print("✅ Loaded weather: \(Int(minRounded)) to \(Int(maxRounded)) (\(isCelsius ? "°C" : "°F"))")
    }
    
    // MARK: - Apply Weather to Item
    private func applyWeatherToItem() {
        // Check if manual input is valid
        guard let manualMin = Double(manualMinInput),
              let manualMax = Double(manualMaxInput),
              manualMin < manualMax,
              (manualMax - manualMin) >= 1.0 else {
            // Clear weather data if input is invalid
            // Use setValue to properly trigger change notifications
            _ = item.primitiveValue(forKey: "minTemperature")
            _ = item.primitiveValue(forKey: "maxTemperature")
            _ = item.primitiveValue(forKey: "temperatureUnit")
            
            item.setValue(nil, forKey: "minTemperature")
            item.setValue(nil, forKey: "maxTemperature")
            item.setValue(nil, forKey: "temperatureUnit")
            
            // Mark item as changed to trigger UI refresh
            item.objectWillChange.send()
            viewContext.processPendingChanges()
            
            // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
            // If viewContext has a parent, we're in a child context and shouldn't save
            if viewContext.parent == nil {
                // We're in a parent context (ItemDetailView), save immediately
                do {
                    guard viewContext.hasChanges else {
                        print("⚠️ No changes to save in context")
                        return
                    }
                    
                    // Set updatedAt on item since we're modifying it
                    setUpdatedAt(item)
                    
                    try viewContext.save()
                    viewContext.refresh(item, mergeChanges: false)
                    print("✅ Weather cleared successfully")
                } catch {
                    print("❌ Failed to save weather: \(error.localizedDescription)")
                    if let nsError = error as NSError? {
                        print("❌ Error details: \(nsError.userInfo)")
                    }
                }
            } else {
                print("✅ Weather cleared in child context (will be saved with item)")
            }
            // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
            return
        }
        
        // Apply constraints
        let constrainedMin = max(manualMin, self.minLimit)
        let constrainedMax = min(manualMax, self.maxLimit)
        
        // Ensure min is still at least 1 less than max after constraints
        guard constrainedMin < constrainedMax, (constrainedMax - constrainedMin) >= 1.0 else {
            return
        }
        
        let minValue = constrainedMin
        let maxValue = constrainedMax
        
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
        
        // Validate converted values before saving
        guard minC.isFinite && maxC.isFinite,
              !minC.isNaN && !maxC.isNaN,
              minC < maxC else {
            print("❌ Invalid temperature values to save: minC=\(minC), maxC=\(maxC)")
            return
        }
        
        // Save to Core Data - use setValue to properly trigger change notifications
        // First ensure the values are accessed (not faults)
        _ = item.primitiveValue(forKey: "minTemperature")
        _ = item.primitiveValue(forKey: "maxTemperature")
        _ = item.primitiveValue(forKey: "temperatureUnit")
        
        // Now set the values using setValue which properly notifies Core Data
        item.setValue(minC, forKey: "minTemperature")
        item.setValue(maxC, forKey: "maxTemperature")
        item.setValue(temperatureUnit, forKey: "temperatureUnit")
        
        // Debug: Print what we're saving
        print("💾 Saving weather: minC=\(minC), maxC=\(maxC), unit=\(temperatureUnit), displayMin=\(Int(minValue)), displayMax=\(Int(maxValue))")
        
        // Mark item as changed to trigger UI refresh
        item.objectWillChange.send()
        
        // Process pending changes to ensure Core Data tracks the changes
        viewContext.processPendingChanges()
        
        // Set updatedAt since we're modifying the item
        setUpdatedAt(item)
        
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
                
                // Trigger automatic sync for the modified item
                SyncService.shared.syncItemIfNeeded(item)
                
                // Verify the save by reading back the values
                viewContext.refresh(item, mergeChanges: false)
                if let savedMinC = item.primitiveValue(forKey: "minTemperature") as? Double,
                   let savedMaxC = item.primitiveValue(forKey: "maxTemperature") as? Double,
                   let savedUnit = item.primitiveValue(forKey: "temperatureUnit") as? String {
                    print("✅ Weather saved successfully to persistent store: minC=\(savedMinC), maxC=\(savedMaxC), unit=\(savedUnit)")
                } else {
                    print("⚠️ Warning: Weather save may have failed - values not found after save")
                }
            } catch {
                print("❌ Failed to save weather: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("❌ Error details: \(nsError.userInfo)")
                }
            }
        } else {
            // We're in a child context (ItemAddView), changes will be saved when parent saves
            print("✅ Weather set in child context (will be saved with item)")
        }
    }
    
    // MARK: - Save Weather
    private func saveWeather() {
        applyWeatherToItem()
        dismiss()
    }
    
    // MARK: - Validate Inputs (similar to Apple's TextField validation)
    private func validateMinInput() {
        guard let value = Double(manualMinInput),
              value.isFinite,
              !value.isNaN else {
            // If invalid, revert to slider value
            manualMinInput = String(Int(round(sliderMinValue)))
            return
        }
        
        // Validate and constrain: min(max(bounds.lowerBound, value), maxValue)
        let validatedValue = min(max(self.minLimit, value), sliderMaxValue - 1)
        sliderMinValue = validatedValue
        manualMinInput = String(Int(round(validatedValue)))
    }
    
    private func validateMaxInput() {
        guard let value = Double(manualMaxInput),
              value.isFinite,
              !value.isNaN else {
            // If invalid, revert to slider value
            manualMaxInput = String(Int(round(sliderMaxValue)))
            return
        }
        
        // Validate and constrain: max(min(bounds.upperBound, value), minValue)
        let validatedValue = max(min(self.maxLimit, value), sliderMinValue + 1)
        sliderMaxValue = validatedValue
        manualMaxInput = String(Int(round(validatedValue)))
    }
    
    // MARK: - Update Inputs from Slider
    private func updateMinInputFromSlider() {
        manualMinInput = String(Int(round(sliderMinValue)))
    }
    
    private func updateMaxInputFromSlider() {
        manualMaxInput = String(Int(round(sliderMaxValue)))
    }
}

// MARK: - Range Slider Component
struct RangeSlider: View {
    @Binding var minValue: Double
    @Binding var maxValue: Double
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
                    .frame(
                        width: thumbX(maxValue, width) - thumbX(minValue, width),
                        height: 4
                    )
                    .offset(x: thumbX(minValue, width))
                
                Thumb(x: thumbX(minValue, width))
                    .gesture(dragGesture(isMin: true, width: width))
                
                Thumb(x: thumbX(maxValue, width))
                    .gesture(dragGesture(isMin: false, width: width))
            }
        }
        .frame(height: 32)
    }
    
    private func dragGesture(isMin: Bool, width: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let percent = min(max(0, value.location.x / width), 1)
                let newValue = bounds.lowerBound +
                    percent * (bounds.upperBound - bounds.lowerBound)
                
                if isMin {
                    minValue = min(newValue, maxValue - 1)
                } else {
                    maxValue = max(newValue, minValue + 1)
                }
            }
    }
    
    private func thumbX(_ value: Double, _ width: CGFloat) -> CGFloat {
        CGFloat((value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * width
    }
}

// MARK: - Thumb Component
struct Thumb: View {
    let x: CGFloat
    
    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: 20, height: 20)
            .shadow(radius: 2)
            .offset(x: x - 10)
    }
}
