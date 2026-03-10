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
    @State private var selectedEventForNavigation: Event?
    @State private var navigateToOutfits = false
    @State private var navigateToItems = false

    @FetchRequest private var events: FetchedResults<Event>

    init(selectedDate: Date, onDismiss: @escaping () -> Void, onNavigateDate: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.onDismiss = onDismiss
        self.onNavigateDate = onNavigateDate
        
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let request: NSFetchRequest<Event> = Event.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.createdAt, ascending: false)]

        // Use startDate instead of date, and exclude soft-deleted events
        let datePredicate = NSPredicate(format: "startDate >= %@ AND startDate < %@", startOfDay as NSDate, endOfDay as NSDate)
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, softDeleteFilter])

        _events = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button(action: { showingCreateEvent = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Event").font(.body)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding()
                
                Divider()
                
                HStack {
                    Button(action: { navigateDate(-1) }) {
                        Image(systemName: "chevron.left").foregroundColor(.primary)
                    }
                    Spacer()
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.body)
                     //   .fontWeight(.semibold)
                    Spacer()
                    Button(action: { navigateDate(1) }) {
                        Image(systemName: "chevron.right").foregroundColor(.primary)
                    }
                }
                .padding(20)
                
                Divider()
                
                // Events list section
                if events.isEmpty {
                    // Empty state - outside of List to avoid dividers
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
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                } else {
                    List {
                        ForEach(events, id: \.objectID) { event in
                            NavigationLink(destination: EventDetailView(event: event)
                                .environment(\.managedObjectContext, viewContext)) {
                                    EventRowView(event: event)
                                }
                               /* .listRowBackground(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue.opacity(0.1))
                                )*/
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let event = events[index]
                                deleteEvent(event)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                Spacer()
            }
            .sheet(isPresented: $showingCreateEvent) {
                CreateEventView(initialDate: selectedDate)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .background(
            Color(.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
       /* .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 { onDismiss() }
                }
        )*/
    }

    private func navigateDate(_ direction: Int) {
        if let newDate = calendar.date(byAdding: .day, value: direction, to: selectedDate) {
            onNavigateDate(newDate)
        }
    }
    
    private func deleteEvent(_ event: Event) {
        withAnimation {
            // Soft delete the event (for sync)
            softDelete(event)
            
            do {
                try viewContext.save()
            } catch {
                print("Error deleting event: \(error)")
            }
        }
    }

}




// MARK: - Event Row View
struct EventRowView: View {
    let event: Event

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
    
    // Helper function to format time, hiding :00 when minutes are zero (e.g., "3:00 PM" -> "3 PM")
    private func formatTime(_ date: Date) -> String {
        let formatted = timeFormatter.string(from: date)
        // Remove ":00" if present (handles both "3:00 PM" and "15:00" formats)
        return formatted.replacingOccurrences(of: ":00", with: "")
    }

    private let imageSize: CGFloat = 120

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // time column
            Text(formatTime(event.startDate ?? Date()))
             //   .font(.caption)
             //   .fontWeight(.medium)
                .foregroundColor(.secondary)
             //   .frame(width: 50)

            // main content (title + horizontally scrollable media)
            VStack(alignment: .leading, spacing: 8) {
                // title + location
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name ?? "Untitled Event")
                        .font(.headline)
                        .foregroundColor(.primary)
/*
                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 0) {
                          //  Text(" at ")
                            Text(location)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                    }*/
                }

                // horizontally scrollable images area
                if hasImages {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            // Outfits first
                            if let outfitsSet = event.outfits as? Set<Outfit>, !outfitsSet.isEmpty {
                                ForEach(Array(outfitsSet), id: \.objectID) { outfit in
                                    if let imageData = outfit.image,
                                       let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(width: imageSize, height: imageSize)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }

                            // Then individual items
                            if let itemsOrderedSet = event.items as? NSOrderedSet, itemsOrderedSet.count > 0 {
                                ForEach(itemsOrderedSet.array as? [Item] ?? [], id: \.objectID) { item in
                                    if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                                       let data = primaryPhoto.data,
                                       let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(width: imageSize, height: imageSize)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .background(Color.white)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: imageSize)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
      //  .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasImages: Bool {
        let hasOutfits = (event.outfits as? Set<Outfit>)?.isEmpty == false
        let hasItems = (event.items as? NSOrderedSet)?.count ?? 0 > 0
        return hasOutfits || hasItems
    }
}



/*
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
        let now = Date()
        newEvent.timestamp = now
        newEvent.createdAt = now
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving event: \(error)")
        }
    }
}



*/
