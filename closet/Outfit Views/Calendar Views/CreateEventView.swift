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

struct CreateEventView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var eventName = "Add title"
    @State private var eventLocation = ""
    
    @State private var selectedLocationTitle: String? = nil
    @State private var selectedLocationSubtitle: String? = nil
    @State private var selectedPlacemark: CLPlacemark? = nil
    
    @StateObject private var searchManager = LocationSearchManager()
    
    @State private var startDate: Date
    @State private var endDate: Date
    
    init(initialDate: Date) {
        _startDate = State(initialValue: initialDate)
        _endDate = State(initialValue: initialDate.addingTimeInterval(3600))
    }
    
    var body: some View {
        NavigationView {
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
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                  //  .overlay(Divider().offset(y: 18), alignment: .bottom)
                    Divider()
                    // MARK: - Location
                    NavigationLink(
                        destination: LocationSearchView(searchManager: searchManager) { suggestion in
                            selectSuggestion(suggestion)
                        }
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.gray)
                                .frame(width: 22)
                              //  .padding(.top, 2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedLocationTitle ?? "Add location (optional)")
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
                            
                            if selectedLocationTitle != nil {
                                Button(action: clearLocation) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    
                    Divider()
                    // MARK: - Date & Time
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .foregroundColor(.gray)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 8) {
                                DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                                DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                            }
                        }
                        
                        if endDate < startDate {
                            Text("End time must be after start time.")
                                .font(.footnote)
                                .foregroundColor(.red)
                                .padding(.leading, 34)
                        } else {
                            Text(durationString)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.leading, 34)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    Divider()
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: saveEvent)
                        .disabled(eventName.isEmpty || (eventLocation.isEmpty == false && selectedPlacemark == nil))
                }
            }
        }
    }
    
    // MARK: - Duration
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
                
                let parts = [
                    placemark.name,
                    placemark.thoroughfare,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.postalCode
                ].compactMap { $0 }
                eventLocation = parts.joined(separator: ", ")
            }
        }
    }
    
    private func clearLocation() {
        selectedPlacemark = nil
        selectedLocationTitle = nil
        selectedLocationSubtitle = nil
        eventLocation = ""
    }
    
    // MARK: - Save
    private func saveEvent() {
        guard selectedPlacemark != nil || eventLocation.isEmpty else { return }
        
        let newEvent = Event(context: viewContext)
        newEvent.id = UUID()
        newEvent.name = eventName
        newEvent.location = eventLocation.isEmpty ? nil : eventLocation
        newEvent.startDate = startDate
        newEvent.endDate = endDate
        newEvent.timestamp = Date()
        
        if let placemark = selectedPlacemark {
            newEvent.latitude = placemark.location?.coordinate.latitude ?? 0
            newEvent.longitude = placemark.location?.coordinate.longitude ?? 0
            
            if let postalAddress = placemark.postalAddress {
                let formatter = CNPostalAddressFormatter()
                newEvent.fullAddress = formatter.string(from: postalAddress).replacingOccurrences(of: "\n", with: ", ")
            }
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


