// MARK: - Event Drawer View
struct EventDrawerView: View {
    let selectedDate: Date
    let events: [Event]
    let onDismiss: () -> Void
    let onNavigateDate: (Date) -> Void
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
           // SelectionHeader(title: dateFormatter.string(from: selectedDate))
            /* Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
            */
            // Header with date navigation
            HStack {
                Button(action: { navigateDate(-1) }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text(dateFormatter.string(from: selectedDate))
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { navigateDate(1) }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.primary)
                }
            }
            .padding(20)
      //      .padding(.vertical, 16)
            
            Divider()
            
            // Events list
            if events.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No events scheduled")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap 'New Event' to add an event")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(events, id: \.objectID) { event in
                            EventRowView(event: event)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            
            Spacer()
        }
        .presentationDetents([.medium, .large])
        .background(
            Color(.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
      //  .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 {
                        onDismiss()
                    }
                }
        )
    }
    
    private func navigateDate(_ direction: Int) {
        if let newDate = calendar.date(byAdding: .day, value: direction, to: selectedDate) {
            onNavigateDate(newDate)
        }
    }
}

// MARK: - Event Row View
struct EventRowView: View {
    let event: Event
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        HStack(spacing: 12) {
            // Time indicator
            VStack(alignment: .leading) {
                Text(timeFormatter.string(from: event.time ?? Date()))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .frame(width: 60, alignment: .leading)
            
            // Event content
            VStack(alignment: .leading, spacing: 4) {
                Text(event.name ?? "Untitled Event")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Outfit count
                let outfitCount = (event.outfits as? Set<Outfit>)?.count ?? 0
                if outfitCount > 0 {
                    Text("\(outfitCount) outfit\(outfitCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Create Event View
struct CreateEventView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var eventName = "Outfit of the Day"
    @State private var eventLocation = ""
    @State private var eventDate = Date()
    @State private var eventTime = Date()
    
    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    TextField("Event Name", text: $eventName)
                    TextField("Location (Optional)", text: $eventLocation)
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveEvent()
                    }
                    .disabled(eventName.isEmpty)
                }
            }
        }
    }
    
    private func saveEvent() {
        let newEvent = Event(context: viewContext)
        newEvent.id = UUID()
        newEvent.name = eventName
        newEvent.location = eventLocation.isEmpty ? nil : eventLocation

        // Normalize the date to include only the day
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