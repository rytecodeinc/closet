//
//  EventAddView.swift
//  closet
//
//  Created by Dan Warner on 10/11/25.
//

import SwiftUI
import MapKit
import Combine
import Contacts
import CoreData

struct EventAddView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession
    
    let eventToEdit: Event?
    @Binding var navigationPath: NavigationPath
    
    /// Account that owns new calendar rows (matches `Event.userId` filtering elsewhere).
    private var calendarAccountUserId: String? {
        authSession.userId?.uuidString
    }
    
    @EnvironmentObject private var locationDraft: EventLocationDraft
    
    @State private var eventName = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var eventNotes = ""
    @State private var isAllDay = false
    @State private var eventVisibility: WardrobeVisibility = .private
    @FocusState private var isNotesFocused: Bool
    @FocusState private var isEventNameFocused: Bool
    
    @State private var tempEvent: Event?
    @State private var refreshToken = UUID() // Force view refresh when items change
    
    @State private var showDiscardAlert = false
    @State private var didCaptureOriginals = false
    @State private var originalName = ""
    @State private var originalLocation = ""
    @State private var originalNotes = ""
    @State private var originalStartDate = Date()
    @State private var originalEndDate = Date()
    @State private var originalIsAllDay = false
    @State private var originalVisibility: WardrobeVisibility = .private
    @State private var originalLatitude: Double = 0
    @State private var originalLongitude: Double = 0
    @State private var originalFullAddress: String? = nil
    @State private var originalItems: [Item] = []
    @State private var originalOutfits: [Outfit] = []
    
    // Computed property to get selected items array (preserves insertion order)
    private var selectedItems: [Item] {
        guard let event = tempEvent,
              let itemsOrderedSet = event.items as? NSOrderedSet else { return [] }
        return itemsOrderedSet.array as? [Item] ?? []
    }

    private var selectedOutfits: [Outfit] {
        guard let event = tempEvent,
              let outfitsSet = event.outfits as? Set<Outfit> else { return [] }
        return outfitsSet.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    
    init(
        eventToEdit: Event? = nil,
        initialDate: Date = Date(),
        navigationPath: Binding<NavigationPath>
    ) {
        self.eventToEdit = eventToEdit
        self._navigationPath = navigationPath
        if let event = eventToEdit {
            _startDate = State(initialValue: event.startDate ?? initialDate)
            _endDate = State(initialValue: event.endDate ?? initialDate.addingTimeInterval(3600))
        } else {
            _startDate = State(initialValue: initialDate)
            _endDate = State(initialValue: initialDate.addingTimeInterval(3600))
        }
    }
    
    var body: some View {
        createEventForm
            .onChange(of: navigationPath.count) { _, _ in
                refreshToken = UUID()
                if let event = tempEvent {
                    viewContext.refresh(event, mergeChanges: true)
                }
            }
    }
    
    private var createEventForm: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // MARK: - Event Name
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "calendar")
                            .foregroundColor(.gray)
                            .frame(width: 22)
                        TextField("Event Name", text: $eventName)
                            .font(.title3)
                            .fontWeight(.medium)
                            .textInputAutocapitalization(.words)
                            .focused($isEventNameFocused)
                    }
                    .padding(.top, 4)
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
                                Toggle("All-day", isOn: $isAllDay)
                                    .onChange(of: isAllDay) { newValue in
                                        let calendar = Calendar.current
                                        if newValue {
                                            startDate = calendar.startOfDay(for: startDate)
                                            endDate = calendar.startOfDay(for: endDate)
                                            if endDate < startDate {
                                                endDate = startDate
                                            }
                                        } else {
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
                                
                                DatePicker("Start", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .frame(height: 34)
                                    .onChange(of: startDate) { newStartDate in
                                        if isAllDay {
                                            let startDay = Calendar.current.startOfDay(for: newStartDate)
                                            let endDay = Calendar.current.startOfDay(for: endDate)
                                            if endDay < startDay {
                                                endDate = startDay
                                            }
                                        } else if endDate <= newStartDate {
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
                        UIDatePicker.appearance().minuteInterval = 5
                    }
                    .padding(.horizontal)

                    Divider()

                    // MARK: - Location
                    Button {
                        isEventNameFocused = false
                        isNotesFocused = false
                        navigationPath.append(CalendarRoute.location)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.gray)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(locationDraft.selectedTitle ?? "Location")
                                    .foregroundColor(locationDraft.selectedTitle == nil ? .secondary : .primary)

                                if let subtitle = locationDraft.selectedSubtitle {
                                    Text(subtitle)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 12)
                        }
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 4)

                    if appCapabilities.enablesCloudSync {
                        Divider()
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: eventVisibility.iconName)
                                .foregroundColor(.gray)
                                .frame(width: 22)
                            Text("Privacy")
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Picker("Privacy", selection: $eventVisibility) {
                                ForEach(WardrobeVisibility.allCases) { value in
                                    Text(value.menuLabel).tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal)
                    }

                    Divider()
                    EventItemsSelectionSection(items: selectedItems, outfits: selectedOutfits) {
                        openItemsSelection()
                    }
                    .id(refreshToken)
                    .padding(.horizontal)

                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "note.text")
                            .foregroundColor(.gray)
                            .frame(width: 22)
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $eventNotes)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, -4)
                                .padding(.vertical, -8)
                                .focused($isNotesFocused)
                            
                            if eventNotes.isEmpty {
                                Text("Notes")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 4)
            }
            .background(Color(.systemBackground))
            .navigationTitle(eventToEdit == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .onAppear {
                guard !didCaptureOriginals else { return }
                if let event = eventToEdit {
                    loadEventForEditing(event)
                    tempEvent = event // Use existing event when editing
                }
                // Don't create temp event here - only create when needed (navigation or save)
                captureOriginals()
                didCaptureOriginals = true
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: attemptCancel) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(hasUnsavedChanges ? "Cancel" : "Back")
                        }
                    }
                    .accessibilityLabel(hasUnsavedChanges ? "Cancel" : "Back")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: saveEvent)
                        .disabled(!canSaveEvent)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        isNotesFocused = false
                        isEventNameFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Dismiss Keyboard")
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) {
                    cancelEditing(discardingChanges: true)
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved edits. Going back will discard them.")
            }
    }
    
    // MARK: - Validation
    /// Title plus a valid date range (timed or all-day) are required to save.
    private var canSaveEvent: Bool {
        let hasTitle = !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasValidDateTime: Bool
        if isAllDay {
            hasValidDateTime = Calendar.current.startOfDay(for: endDate)
                >= Calendar.current.startOfDay(for: startDate)
        } else {
            hasValidDateTime = endDate > startDate
        }
        let locationOK = locationDraft.eventLocation.isEmpty || locationDraft.selectedPlacemark != nil
        return hasTitle && hasValidDateTime && locationOK
    }

    private var hasUnsavedChanges: Bool {
        if eventName.trimmingCharacters(in: .whitespacesAndNewlines)
            != originalName.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        if locationDraft.eventLocation != originalLocation { return true }
        if eventNotes != originalNotes { return true }
        if isAllDay != originalIsAllDay { return true }
        if eventVisibility != originalVisibility { return true }
        if !datesMatchForEdit(startDate, originalStartDate) { return true }
        if !datesMatchForEdit(endDate, originalEndDate) { return true }
        if selectedItems.map(\.objectID) != originalItems.map(\.objectID) { return true }
        if Set(selectedOutfits.map(\.objectID)) != Set(originalOutfits.map(\.objectID)) { return true }
        return false
    }

    private func datesMatchForEdit(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.compare(lhs, to: rhs, toGranularity: .minute) == .orderedSame
    }

    private func captureOriginals() {
        originalName = eventName
        originalLocation = locationDraft.eventLocation
        originalNotes = eventNotes
        originalStartDate = startDate
        originalEndDate = endDate
        originalIsAllDay = isAllDay
        originalVisibility = eventVisibility
        originalItems = selectedItems
        originalOutfits = selectedOutfits
        if let event = eventToEdit ?? tempEvent {
            originalLatitude = event.latitude
            originalLongitude = event.longitude
            originalFullAddress = event.fullAddress
        } else {
            originalLatitude = 0
            originalLongitude = 0
            originalFullAddress = nil
        }
    }

    private func attemptCancel() {
        if hasUnsavedChanges {
            showDiscardAlert = true
        } else {
            cancelEditing(discardingChanges: false)
        }
    }

    private func openItemsSelection() {
        if tempEvent == nil {
            createTempEvent()
        } else {
            updateTempEvent()
        }
        guard let event = tempEvent else { return }
        if event.objectID.isTemporaryID {
            do {
                try viewContext.obtainPermanentIDs(for: [event])
            } catch {
                print("Error obtaining permanent ID for event before items selection: \(error)")
                return
            }
        }
        navigationPath.append(CalendarRoute.items(event.objectID.uriRepresentation().absoluteString))
    }

    private func cancelEditing(discardingChanges: Bool) {
        if let event = eventToEdit {
            if discardingChanges {
                restoreEventFromOriginals(event)
            }
            dismiss()
            return
        }

        // New event: remove any temp/draft row created during this session.
        if let event = tempEvent {
            if event.objectID.isTemporaryID {
                viewContext.delete(event)
            } else {
                softDelete(event)
                do {
                    try viewContext.save()
                    SyncService.shared.syncEventIfNeeded(event)
                } catch {
                    print("Error soft-deleting unsaved event: \(error)")
                }
            }
        }
        dismiss()
    }

    private func restoreEventFromOriginals(_ event: Event) {
        event.name = originalName.isEmpty ? nil : originalName
        event.location = originalLocation.isEmpty ? nil : originalLocation
        event.notes = originalNotes.isEmpty ? nil : originalNotes
        event.startDate = originalStartDate
        event.endDate = originalEndDate
        event.eventVisibility = originalVisibility
        event.latitude = originalLatitude
        event.longitude = originalLongitude
        event.fullAddress = originalFullAddress

        if let existingItems = event.items as? NSOrderedSet {
            event.removeFromItems(existingItems)
        }
        for item in originalItems {
            event.addToItems(item)
        }

        if let existingOutfits = event.outfits as? Set<Outfit> {
            for outfit in existingOutfits {
                event.removeFromOutfits(outfit)
            }
        }
        for outfit in originalOutfits {
            event.addToOutfits(outfit)
        }

        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
            SyncService.shared.syncEventIfNeeded(event)
        } catch {
            print("Error restoring event after discard: \(error)")
        }
    }

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
    // MARK: - Load Event for Editing
    private func loadEventForEditing(_ event: Event) {
        eventName = event.name ?? ""
        locationDraft.reset()
        locationDraft.eventLocation = event.location ?? ""
        eventNotes = event.notes ?? ""
        eventVisibility = event.eventVisibility
        
        if let location = event.location {
            locationDraft.selectedTitle = location
        }
        if let fullAddress = event.fullAddress {
            locationDraft.selectedSubtitle = fullAddress
        }
        
        if let latitude = event.latitude as Double?, latitude != 0,
           let longitude = event.longitude as Double?, longitude != 0 {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                if let placemark = placemarks?.first {
                    DispatchQueue.main.async {
                        locationDraft.selectedPlacemark = placemark
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
                newEvent.eventVisibility = .private
                setCreatedAndUpdatedAt(newEvent)
            }
            // Set initial values, will be updated on save
            newEvent.name = eventName.isEmpty ? nil : eventName
            newEvent.location = locationDraft.eventLocation.isEmpty ? nil : locationDraft.eventLocation
            newEvent.startDate = startDate
            newEvent.endDate = endDate
            newEvent.timestamp = eventToEdit?.timestamp ?? Date()
            newEvent.notes = {
                let trimmed = eventNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()
            newEvent.eventVisibility = eventVisibility
            
            if let placemark = locationDraft.selectedPlacemark {
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
        event.location = locationDraft.eventLocation.isEmpty ? nil : locationDraft.eventLocation
        event.startDate = startDate
        event.endDate = endDate
        event.notes = {
            let trimmed = eventNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        event.eventVisibility = eventVisibility
        
        if let placemark = locationDraft.selectedPlacemark {
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
        guard canSaveEvent else { return }

        // Ensure temp event exists and is updated
        if tempEvent == nil {
            createTempEvent()
        } else {
            updateTempEvent()
        }

        guard let event = tempEvent else { return }

        event.name = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = eventNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        event.eventVisibility = eventVisibility

        syncEventUserIdFromLinkedEntities(event)
        if (event.userId == nil || (event.userId ?? "").isEmpty), let uid = calendarAccountUserId {
            event.userId = uid
        }

        if event.createdAt == nil {
            setCreatedAndUpdatedAt(event)
        } else {
            setUpdatedAt(event)
        }

        do {
            try viewContext.save()
            SyncService.shared.syncEventIfNeeded(event)
            dismiss()
        } catch {
            print("Error saving event: \(error)")
        }
    }
}



// MARK: - Location Search View
struct LocationSearchView: View {
    @EnvironmentObject private var locationDraft: EventLocationDraft
    @StateObject private var searchManager = LocationSearchManager()
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search location", text: $query)
                    .focused($isTextFieldFocused)
                    .onChange(of: query) { newValue in
                        searchManager.updateQuery(newValue)
                    }
                    .textFieldStyle(.plain)

                if !query.isEmpty {
                    Button {
                        query = ""
                        searchManager.updateQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear location search")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)

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
                            selectSuggestion(suggestion)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .animation(.easeInOut, value: searchManager.suggestions.count)
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if query.isEmpty {
                let existing = locationDraft.selectedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? locationDraft.eventLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                if !existing.isEmpty {
                    query = existing
                    searchManager.updateQuery(existing)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }

    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: suggestion)
        MKLocalSearch(request: request).start { response, _ in
            guard let placemark = response?.mapItems.first?.placemark else { return }
            DispatchQueue.main.async {
                locationDraft.selectedPlacemark = placemark
                locationDraft.selectedTitle = suggestion.title
                locationDraft.selectedSubtitle = suggestion.subtitle
                locationDraft.eventLocation = placemark.name ?? suggestion.title
                dismiss()
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


