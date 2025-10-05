//
//  EventDrawerView.swift
//  closet
//
//  Created by Dan Warner on 9/20/25.
//

import Foundation
import SwiftUI
import CoreData

// MARK: - Event Drawer View
struct EventDrawerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    let selectedDate: Date
    let onDismiss: () -> Void
    let onNavigateDate: (Date) -> Void
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()
    
    @State private var showingCreateEvent = false
    
    // 👇 Dynamic fetch request bound to selectedDate
    @FetchRequest private var events: FetchedResults<Event>
    
    init(
        selectedDate: Date,
        onDismiss: @escaping () -> Void,
        onNavigateDate: @escaping (Date) -> Void
    ) {
        self.selectedDate = selectedDate
        self.onDismiss = onDismiss
        self.onNavigateDate = onNavigateDate
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.timestamp, ascending: false)]
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        
        _events = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: { showingCreateEvent = true }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Event")
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding()
            
            Divider()
            
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
                            NavigationLink(
                                destination: EventOutfitSelectionView(event: event)
                                    .environment(\.managedObjectContext, viewContext)
                            ) {
                                EventRowView(event: event)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            
            Spacer()
        }
        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView(initialDate: selectedDate)
                .environment(\.managedObjectContext, viewContext)
        }
        .background(
            Color(.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
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
                    
                    // Outfit images
                    if let outfitsSet = event.outfits as? Set<Outfit>, !outfitsSet.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(outfitsSet.prefix(3)), id: \.objectID) { outfit in
                                if let imageData = outfit.image,
                                   let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                                        )
                                }
                            }
                            if outfitsSet.count > 3 {
                                Text("+\(outfitsSet.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    .padding(.leading, 2)
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

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
    @State private var eventDate: Date
    @State private var eventTime = Date()
    
    // 👇 Custom initializer to allow pre-filling with selectedDate
    init(initialDate: Date) {
        _eventDate = State(initialValue: initialDate)
    }
    
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveEvent() }
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



