import SwiftUI
import CoreData

struct OutfitCalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    // Fetch events for the current visible date range
    @FetchRequest(
        entity: Event.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.date, ascending: true)]
    ) var events: FetchedResults<Event>
    
    @State private var selectedDate: Date? = nil
    @State private var showingEventDrawer = false
    @State private var showingCreateEvent = false
    @State private var scrollViewID = UUID()
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Calendar scroll view
                    calendarScrollView
                }
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("New Event") {
                            showingCreateEvent = true
                        }
                    }
                }
                
                // Event drawer
                if showingEventDrawer, let selectedDate = selectedDate {
                    EventDrawerView(
                        selectedDate: selectedDate,
                        events: eventsForDate(selectedDate),
                        onDismiss: {
                            showingEventDrawer = false
                            self.selectedDate = nil
                        },
                        onNavigateDate: { newDate in
                            self.selectedDate = newDate
                        }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView()
                .environment(\.managedObjectContext, viewContext)
        }
    }
    
    // MARK: - Calendar Scroll View
    private var calendarScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(monthsToDisplay, id: \.self) { month in
                        monthView(for: month)
                            .id(month)
                    }
                }
            }
            .onAppear {
                // Scroll to current month on appear
                proxy.scrollTo(startOfMonth(for: Date()), anchor: .top)
            }
        }
    }
    
    // MARK: - Month View
    private func monthView(for month: Date) -> some View {
        VStack(spacing: 0) {
            // Month header
            monthHeader(for: month)
            
            // Days of week header
            daysOfWeekHeader
            
            // Calendar grid
            calendarGrid(for: month)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }
    
    private func monthHeader(for month: Date) -> some View {
        HStack {
            Text(monthYearString(for: month))
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.vertical, 16)
    }
    
    private var daysOfWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                Text(String(day.prefix(1)))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Calendar Grid
    private func calendarGrid(for month: Date) -> some View {
        let days = daysInMonth(month)
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        
        return LazyVGrid(columns: columns, spacing: 1) {
            ForEach(days, id: \.self) { day in
                if calendar.isDate(day, equalTo: month, toGranularity: .month) {
                    dayCell(for: day)
                } else {
                    // Empty cell for days outside current month
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 50)
                }
            }
        }
        .background(
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1),
            alignment: .top
        )
    }
    
    // MARK: - Day Cell
    private func dayCell(for date: Date) -> some View {
        let dayEvents = eventsForDate(date)
        let isSelected = selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!)
        let isToday = calendar.isDateInToday(date)
        
        return VStack(spacing: 2) {
            ZStack {
                // Background for today/selected
                if isToday || isSelected {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.blue.opacity(0.2))
                        .frame(width: 32, height: 32)
                }
                
                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isToday ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : (isToday ? .blue : .primary))
            }
            
            // Event indicators
            HStack(spacing: 1) {
                ForEach(0..<min(dayEvents.count, 3), id: \.self) { _ in
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 4, height: 4)
                }
                if dayEvents.count > 3 {
                    Text("+")
                        .font(.system(size: 8))
                        .foregroundColor(.blue)
                }
            }
            .frame(height: 8)
        }
        .frame(height: 50)
        .contentShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .onTapGesture {
            selectedDate = date
            withAnimation(.easeInOut(duration: 0.3)) {
                showingEventDrawer = true
            }
        }
    }
    
    // MARK: - Helper Functions
    private var monthsToDisplay: [Date] {
        let currentDate = Date()
        var months: [Date] = []
        
        // Show 6 months before and after current month
        for i in -6...6 {
            if let month = calendar.date(byAdding: .month, value: i, to: currentDate) {
                months.append(startOfMonth(for: month))
            }
        }
        return months
    }
    
    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
    
    private func daysInMonth(_ month: Date) -> [Date] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: month),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let paddingDays = firstWeekday - calendar.firstWeekday
        
        var days: [Date] = []
        
        // Add padding days from previous month
        if paddingDays > 0 {
            for i in (1...paddingDays).reversed() {
                if let day = calendar.date(byAdding: .day, value: -i, to: firstOfMonth) {
                    days.append(day)
                }
            }
        }
        
        // Add days of current month
        for day in monthRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        
        // Add padding days from next month to complete the grid
        let remainingCells = 42 - days.count // 6 weeks * 7 days
        if remainingCells > 0 {
            let lastDayOfMonth = days.last ?? firstOfMonth
            for i in 1...remainingCells {
                if let day = calendar.date(byAdding: .day, value: i, to: lastDayOfMonth) {
                    days.append(day)
                }
            }
        }
        
        return days
    }
    
    private func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func eventsForDate(_ date: Date) -> [Event] {
        return events.filter { event in
            calendar.isDate(event.date ?? Date(), inSameDayAs: date)
        }
    }
}

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
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
            
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
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
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
        .background(
            Color(.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
        .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.y > 100 {
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
        newEvent.date = eventDate
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