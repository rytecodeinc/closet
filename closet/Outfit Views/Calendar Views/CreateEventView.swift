//
//  CreateEventView.swift
//  closet
//
//  Created by Dan Warner on 10/11/25.
//

import SwiftUI
import MapKit
import Combine
import Contacts
import CoreData

struct CreateEventView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let eventToEdit: Event?
    
    /// Account that owns new calendar rows (matches `Event.userId` filtering elsewhere).
    private var calendarAccountUserId: String? {
        SupabaseService.shared.currentUser?.id.uuidString
    }
    
    @State private var eventName = ""
    @State private var eventLocation = ""
    
    @State private var selectedLocationTitle: String? = nil
    @State private var selectedLocationSubtitle: String? = nil
    @State private var selectedPlacemark: CLPlacemark? = nil
    
    @StateObject private var searchManager = LocationSearchManager()
    
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var eventNotes = ""
    @State private var isAllDay = false
    
    // Outfit/Item selection
    @State private var navigateToOutfits = false
    @State private var navigateToItems = false
    @State private var tempEvent: Event?
    @State private var refreshToken = UUID() // Force view refresh when items change
    
    // Computed property to get selected items count
    private var selectedItemsCount: Int {
        guard let event = tempEvent,
              let itemsOrderedSet = event.items as? NSOrderedSet else { return 0 }
        return itemsOrderedSet.count
    }
    
    // Computed property to get selected items array (preserves insertion order)
    private var selectedItems: [Item] {
        guard let event = tempEvent,
              let itemsOrderedSet = event.items as? NSOrderedSet else { return [] }
        return itemsOrderedSet.array as? [Item] ?? []
    }
    
    // Computed property to get selected outfits count
    private var selectedOutfitsCount: Int {
        guard let event = tempEvent,
              let outfitsSet = event.outfits as? Set<Outfit> else { return 0 }
        return outfitsSet.count
    }
    
    // Computed property to get selected outfits array
    private var selectedOutfits: [Outfit] {
        guard let event = tempEvent,
              let outfitsSet = event.outfits as? Set<Outfit> else { return [] }
        return Array(outfitsSet)
    }
    
    private let imageSize: CGFloat = 100
    
    init(eventToEdit: Event? = nil, initialDate: Date = Date()) {
        self.eventToEdit = eventToEdit
        if let event = eventToEdit {
            _startDate = State(initialValue: event.startDate ?? initialDate)
            _endDate = State(initialValue: event.endDate ?? initialDate.addingTimeInterval(3600))
        } else {
            _startDate = State(initialValue: initialDate)
            _endDate = State(initialValue: initialDate.addingTimeInterval(3600))
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    
                    // MARK: - Event Name
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "calendar")
                            .foregroundColor(.gray)
                            .frame(width: 22)
                        TextField("Title", text: $eventName)
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                    .padding(.top, 4)
                    .padding(.horizontal)
                  //  .overlay(Divider().offset(y: 18), alignment: .bottom)
                    Divider()
                    // MARK: - Location
                    ZStack {
                        NavigationLink(
                            destination: LocationSearchView(searchManager: searchManager) { suggestion in
                                selectSuggestion(suggestion)
                            }
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.gray)
                                    .frame(width: 22)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedLocationTitle ?? "Location")
                                        .foregroundColor(selectedLocationTitle == nil ? .secondary : .primary)
                                    
                                    if let subtitle = selectedLocationSubtitle {
                                        Text(subtitle)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                
                                if selectedLocationTitle == nil {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        // Clear button overlay (only when location is selected)
                        if selectedLocationTitle != nil {
                            HStack {
                                Spacer()
                                Button(action: clearLocation) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    // MARK: - Date & Time
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "clock")
                                .foregroundColor(.gray)
                                .frame(width: 22)
                                .padding(.top, 7)
                            
                            VStack(alignment: .leading, spacing: 15) {
                                // All-day toggle
                                Toggle("All-day", isOn: $isAllDay)
                                    .onChange(of: isAllDay) { newValue in
                                        let calendar = Calendar.current
                                        if newValue {
                                            // Switching to all-day: set times to start of day
                                            startDate = calendar.startOfDay(for: startDate)
                                            endDate = calendar.startOfDay(for: endDate)
                                            // Ensure end date is not before start date
                                            if endDate < startDate {
                                                endDate = startDate
                                            }
                                        } else {
                                            // Switching from all-day: preserve dates but set reasonable default times
                                            var components = calendar.dateComponents([.year, .month, .day], from: startDate)
                                            components.hour = 9
                                            components.minute = 0
                                            startDate = calendar.date(from: components) ?? startDate
                                            
                                            components = calendar.dateComponents([.year, .month, .day], from: endDate)
                                            components.hour = 10
                                            components.minute = 0
                                            endDate = calendar.date(from: components) ?? endDate
                                        }
                                    }
                                
                                // Date/Time pickers
                                DatePicker("Start", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .frame(height: 34)
                                    .onChange(of: startDate) { newStartDate in
                                        // Ensure end date is always after start date
                                        if isAllDay {
                                            // For all-day events, ensure end date is on or after start date
                                            let startDay = Calendar.current.startOfDay(for: newStartDate)
                                            let endDay = Calendar.current.startOfDay(for: endDate)
                                            if endDay < startDay {
                                                endDate = startDay
                                            }
                                        } else {
                                            endDate = newStartDate.addingTimeInterval(3600)
                                        }
                                    }
                                
                                DatePicker("End", selection: $endDate, in: minEndDate..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .frame(height: 34)
                            }
                        }
                    }
                    .onAppear {
                        UIDatePicker.appearance().minuteInterval = 5 // set 5 minute increments
                    }
                    .onDisappear {
                        UIDatePicker.appearance().minuteInterval = 1  // restore default
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    // MARK: - Notes/Description
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "note.text")
                            .foregroundColor(.gray)
                            .frame(width: 22)
                           // .padding(.top, 4)
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $eventNotes)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, -4)
                                .padding(.vertical, -8)
                            
                            if eventNotes.isEmpty {
                                Text("Notes")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .padding(.horizontal)
                    Divider()
                    
                    // MARK: - Items Selection
                    ZStack {
                        Button(action: {
                            if tempEvent == nil {
                                createTempEvent()
                            } else {
                                updateTempEvent()
                            }
                            navigateToItems = true
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "tshirt")
                                    .foregroundColor(.gray)
                                    .frame(width: 22)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    if selectedItemsCount > 0 {
                                        Text("\(selectedItemsCount) item\(selectedItemsCount == 1 ? "" : "s") selected")
                                            .foregroundColor(.primary)
                                    } else {
                                        Text("Add items from your closet")
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    // Selected Items Images
                                    if selectedItemsCount > 0 {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(selectedItems, id: \.objectID) { item in
                                                    if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                                                       let data = primaryPhoto.data,
                                                       let uiImage = UIImage(data: data) {
                                                        Image(uiImage: uiImage)
                                                            .resizable()
                                                            .aspectRatio(1, contentMode: .fill)
                                                            .frame(width: 100, height: 100)
                                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    } else if let imageData = item.image,
                                                              let uiImage = UIImage(data: imageData) {
                                                        Image(uiImage: uiImage)
                                                            .resizable()
                                                            .aspectRatio(1, contentMode: .fill)
                                                            .frame(width: 100, height: 100)
                                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 4)
                                                            .fill(Color(.systemGray5))
                                                            .frame(width: 100, height: 100)
                                                            .overlay(
                                                                Image(systemName: "photo")
                                                                    .foregroundColor(.secondary)
                                                                    .font(.caption)
                                                            )
                                                    }
                                                }
                                            }
                                        }
                                        .id(refreshToken) // Force refresh when token changes
                                    }
                                }
                                Spacer()
                                
                                if selectedItemsCount == 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        // Clear button overlay (only when items are selected)
                        if selectedItemsCount > 0, let event = tempEvent {
                            HStack {
                                Spacer()
                                Button(action: {
                                    // Clear all items
                                    for item in selectedItems {
                                        event.removeFromItems(item)
                                    }
                                    refreshToken = UUID() // Trigger refresh
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // MARK: - Outfits Selection
                    ZStack {
                        Button(action: {
                            if tempEvent == nil {
                                createTempEvent()
                            } else {
                                updateTempEvent()
                            }
                            navigateToOutfits = true
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "photo.artframe")
                                    .foregroundColor(.gray)
                                    .frame(width: 22)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    if selectedOutfitsCount > 0 {
                                        Text("\(selectedOutfitsCount) outfit\(selectedOutfitsCount == 1 ? "" : "s") selected")
                                            .foregroundColor(.primary)
                                    } else {
                                        Text("Add outfits")
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    // Selected Outfits Images
                                    if selectedOutfitsCount > 0 {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(selectedOutfits, id: \.objectID) { outfit in
                                                    if let imageData = outfit.image,
                                                       let uiImage = UIImage(data: imageData) {
                                                        Image(uiImage: uiImage)
                                                            .resizable()
                                                            .aspectRatio(1, contentMode: .fill)
                                                            .frame(width: 100, height: 100)
                                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 4)
                                                            .fill(Color(.systemGray5))
                                                            .frame(width: 100, height: 100)
                                                            .overlay(
                                                                Image(systemName: "photo")
                                                                    .foregroundColor(.secondary)
                                                                    .font(.caption)
                                                            )
                                                    }
                                                }
                                            }
                                        }
                                        .id(refreshToken) // Force refresh when token changes
                                    }
                                }
                                Spacer()
                                
                                if selectedOutfitsCount == 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        // Clear button overlay (only when outfits are selected)
                        if selectedOutfitsCount > 0, let event = tempEvent {
                            HStack {
                                Spacer()
                                Button(action: {
                                    // Clear all outfits
                                    for outfit in selectedOutfits {
                                        event.removeFromOutfits(outfit)
                                    }
                                    refreshToken = UUID() // Trigger refresh
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(eventToEdit == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToOutfits) {
                if let event = tempEvent {
                    EventOutfitSelectionView(event: event)
                        .environment(\.managedObjectContext, viewContext)
                }
            }
            .navigationDestination(isPresented: $navigateToItems) {
                if let event = tempEvent {
                    EventIndividualItemSelection(event: event)
                        .environment(\.managedObjectContext, viewContext)
                }
            }
            .onChange(of: navigateToItems) { isNavigating in
                // When returning from item selection (isNavigating becomes false)
                if !isNavigating {
                    // Refresh view to show updated items
                    refreshToken = UUID()
                    // Also refresh the managed object context to ensure we have latest data
                    if let event = tempEvent {
                        viewContext.refresh(event, mergeChanges: true)
                    } else if let event = eventToEdit {
                        viewContext.refresh(event, mergeChanges: true)
                    }
                }
            }
            .onChange(of: navigateToOutfits) { isNavigating in
                // When returning from outfit selection (isNavigating becomes false)
                if !isNavigating {
                    // Refresh view to show updated outfits
                    refreshToken = UUID()
                    // Also refresh the managed object context to ensure we have latest data
                    if let event = tempEvent {
                        viewContext.refresh(event, mergeChanges: true)
                    } else if let event = eventToEdit {
                        viewContext.refresh(event, mergeChanges: true)
                    }
                }
            }
            .onAppear {
                if let event = eventToEdit {
                    loadEventForEditing(event)
                    tempEvent = event // Use existing event when editing
                }
                // Don't create temp event here - only create when needed (navigation or save)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", role: .cancel) {
                        // Clean up temp event only if it was newly created (not editing)
                        // For new events that haven't been saved, we can hard delete
                        if eventToEdit == nil, let event = tempEvent {
                            // If it's a new unsaved event, hard delete is fine
                            // Otherwise soft delete for sync
                            if event.objectID.isTemporaryID {
                                viewContext.delete(event)
                            } else {
                                softDelete(event)
                            }
                        }
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: saveEvent)
                        .disabled(eventName.isEmpty || (eventLocation.isEmpty == false && selectedPlacemark == nil))
                }
            }
        }
    }
    
    // MARK: - Validation
    private var minEndDate: Date {
        if isAllDay {
            // For all-day events, minimum is the start of the start date
            return Calendar.current.startOfDay(for: startDate)
        } else {
            // For timed events, minimum is 1 minute after start
            return startDate.addingTimeInterval(60)
        }
    }
    
    /* MARK: - Duration
    private var durationString: String {
        let seconds = endDate.timeIntervalSince(startDate)
        guard seconds > 0 else { return "Invalid duration" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        
        if days > 0 {
            let remainingHours = hours % 24
            return "\(days) day\(days > 1 ? "s" : "") \(remainingHours) hr"
        } else if hours > 0 {
            let remainingMinutes = minutes % 60
            return "\(hours) hr \(remainingMinutes) min"
        } else {
            return "\(minutes) min"
        }
    }
    */
    // MARK: - Location
    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: suggestion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let placemark = response?.mapItems.first?.placemark else { return }
            selectedPlacemark = placemark
            
            DispatchQueue.main.async {
                selectedLocationTitle = suggestion.title
                selectedLocationSubtitle = suggestion.subtitle

                eventLocation = placemark.name ?? suggestion.title
            }

        }
    }
    
    private func clearLocation() {
        selectedPlacemark = nil
        selectedLocationTitle = nil
        selectedLocationSubtitle = nil
        eventLocation = ""
    }
    
    // MARK: - Load Event for Editing
    private func loadEventForEditing(_ event: Event) {
        eventName = event.name ?? ""
        eventLocation = event.location ?? ""
        eventNotes = event.notes ?? ""
        
        if let location = event.location {
            selectedLocationTitle = location
        }
        if let fullAddress = event.fullAddress {
            selectedLocationSubtitle = fullAddress
        }
        
        if let latitude = event.latitude as Double?, latitude != 0,
           let longitude = event.longitude as Double?, longitude != 0 {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                if let placemark = placemarks?.first {
                    DispatchQueue.main.async {
                        selectedPlacemark = placemark
                    }
                }
            }
        }
        
        // Determine if all-day based on times
        if let start = event.startDate, let end = event.endDate {
            let calendar = Calendar.current
            let startComponents = calendar.dateComponents([.hour, .minute], from: start)
            let endComponents = calendar.dateComponents([.hour, .minute], from: end)
            isAllDay = (startComponents.hour == 0 && startComponents.minute == 0) &&
                       (endComponents.hour == 0 && endComponents.minute == 0)
        }
    }
    
    // MARK: - Temp Event
    private func createTempEvent() {
        if tempEvent == nil {
            // Use existing event if editing, otherwise create new
            let newEvent = eventToEdit ?? Event(context: viewContext)
            if eventToEdit == nil {
                newEvent.id = UUID()
                newEvent.userId = calendarAccountUserId
            }
            // Set initial values, will be updated on save
            newEvent.name = eventName.isEmpty ? nil : eventName
            newEvent.location = eventLocation.isEmpty ? nil : eventLocation
            newEvent.startDate = startDate
            newEvent.endDate = endDate
            newEvent.timestamp = eventToEdit?.timestamp ?? Date()
            newEvent.notes = eventNotes.isEmpty ? nil : eventNotes
            
            if let placemark = selectedPlacemark {
                newEvent.latitude = placemark.location?.coordinate.latitude ?? 0
                newEvent.longitude = placemark.location?.coordinate.longitude ?? 0
                
                if let postalAddress = placemark.postalAddress {
                    let formatter = CNPostalAddressFormatter()
                    newEvent.fullAddress = formatter.string(from: postalAddress).replacingOccurrences(of: "\n", with: ", ")
                }
            }
            
            tempEvent = newEvent
        } else {
            // Update existing temp event with current values
            updateTempEvent()
        }
    }
    
    private func updateTempEvent() {
        guard let event = tempEvent else { return }
        event.name = eventName.isEmpty ? nil : eventName
        event.location = eventLocation.isEmpty ? nil : eventLocation
        event.startDate = startDate
        event.endDate = endDate
        event.notes = eventNotes.isEmpty ? nil : eventNotes
        
        if let placemark = selectedPlacemark {
            event.latitude = placemark.location?.coordinate.latitude ?? 0
            event.longitude = placemark.location?.coordinate.longitude ?? 0
            
            if let postalAddress = placemark.postalAddress {
                let formatter = CNPostalAddressFormatter()
                event.fullAddress = formatter.string(from: postalAddress).replacingOccurrences(of: "\n", with: ", ")
            }
        }
    }
    
    // MARK: - Save
    private func saveEvent() {
        guard selectedPlacemark != nil || eventLocation.isEmpty else { return }
        
        // Ensure temp event exists and is updated
        if tempEvent == nil {
            createTempEvent()
        } else {
            updateTempEvent()
        }
        
        guard let event = tempEvent else { return }
        
        syncEventUserIdFromLinkedEntities(event)
        if (event.userId == nil || (event.userId ?? "").isEmpty), let uid = calendarAccountUserId {
            event.userId = uid
        }
        
        // Set updatedAt if editing existing event
        if tempEvent?.id != nil {
            setUpdatedAt(event)
        }
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving event: \(error)")
        }
    }
}





// MARK: - Location Search View
struct LocationSearchView: View {
    @ObservedObject var searchManager: LocationSearchManager
    var onSelect: (MKLocalSearchCompletion) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var query = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar at the top
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search location", text: $query)
                    .focused($isTextFieldFocused)
                    .onChange(of: query) { newValue in
                        searchManager.updateQuery(newValue)
                    }
                    .textFieldStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal) // spacing from edges
            
            // Suggestions
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(searchManager.suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.gray)
                                .padding(.top, 2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .foregroundColor(.primary)
                                
                                Text(suggestion.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .onTapGesture {
                            onSelect(suggestion)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal)
            }
            .animation(.easeInOut, value: searchManager.suggestions.count)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Autofocus immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}




// MARK: - Location Search Manager
class LocationSearchManager: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }
    
    func updateQuery(_ query: String) {
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.suggestions = completer.results
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Completer error: \(error)")
        DispatchQueue.main.async {
            self.suggestions = []
        }
    }
}


