import SwiftUI
import MapKit

struct CreateEventView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var eventName = "Outfit of the Day"
    @State private var eventLocation = ""
    @State private var eventDate: Date
    @State private var eventTime = Date()
    
    @State private var locationSuggestions: [MKLocalSearchCompletion] = []
    @State private var selectedPlacemark: CLPlacemark? = nil
    
    private var completer = MKLocalSearchCompleter()
    
    init(initialDate: Date) {
        _eventDate = State(initialValue: initialDate)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    TextField("Event Name", text: $eventName)
                    
                    VStack(alignment: .leading) {
                        TextField("Location (Optional)", text: $eventLocation)
                            .onChange(of: eventLocation) { newValue in
                                fetchLocationSuggestions(for: newValue)
                            }
                        
                        // Show suggestions
                        if !locationSuggestions.isEmpty {
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(locationSuggestions, id: \.title) { suggestion in
                                        Text("\(suggestion.title), \(suggestion.subtitle)")
                                            .font(.subheadline)
                                            .padding(4)
                                            .onTapGesture {
                                                selectSuggestion(suggestion)
                                            }
                                    }
                                }
                            }
                            .frame(maxHeight: 150)
                        }
                    }
                }
                
                Section("Date & Time") {
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                    DatePicker("Time", selection: $eventTime, displayedComponents: .hourAndMinute)
                }
            }
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
    
    // MARK: - MapKit integration
    private func fetchLocationSuggestions(for query: String) {
        guard !query.isEmpty else {
            locationSuggestions = []
            return
        }
        
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = query
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, error in
            if let mapItems = response?.mapItems {
                locationSuggestions = mapItems.map { item in
                    MKLocalSearchCompletion(title: item.name ?? "", subtitle: item.placemark.title ?? "")
                }
            } else {
                locationSuggestions = []
            }
        }
    }
    
    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        eventLocation = suggestion.title
        // Confirm placemark exists
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = suggestion.title
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, error in
            if let placemark = response?.mapItems.first?.placemark {
                selectedPlacemark = placemark
            }
        }
        locationSuggestions = []
        hideKeyboard()
    }
    
    private func saveEvent() {
        guard selectedPlacemark != nil || eventLocation.isEmpty else { return }
        
        let newEvent = Event(context: viewContext)
        newEvent.id = UUID()
        newEvent.name = eventName
        newEvent.location = eventLocation.isEmpty ? nil : eventLocation
        newEvent.date = Calendar.current.startOfDay(for: eventDate)
        newEvent.time = eventTime
        newEvent.timestamp = Date()
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving event: \(error)")
        }
    }
}

// Helper to hide keyboard
#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
