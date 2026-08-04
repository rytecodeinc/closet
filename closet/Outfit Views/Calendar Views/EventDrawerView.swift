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
    /// Events are scoped to this Supabase user id; when nil, the list is empty.
    let ownerUserId: String?
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

    init(
        selectedDate: Date,
        ownerUserId: String?,
        onDismiss: @escaping () -> Void,
        onNavigateDate: @escaping (Date) -> Void
    ) {
        self.selectedDate = selectedDate
        self.ownerUserId = ownerUserId
        self.onDismiss = onDismiss
        self.onNavigateDate = onNavigateDate
        
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let request: NSFetchRequest<Event> = Event.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.startDate, ascending: true)]

        // Use startDate instead of date, exclude soft-deleted events, and scope to account
        let datePredicate = NSPredicate(format: "startDate >= %@ AND startDate < %@", startOfDay as NSDate, endOfDay as NSDate)
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        let userPredicate: NSPredicate
        if let uid = ownerUserId, !uid.isEmpty {
            userPredicate = NSPredicate(format: "userId == %@", uid)
        } else {
            userPredicate = NSPredicate(value: false)
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            datePredicate, softDeleteFilter, userPredicate,
        ])

        _events = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Button(action: { navigateDate(-1) }) {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(.primary)
                                    .frame(width: 28, height: 44)
                            }
                            Button(action: { navigateDate(1) }) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.primary)
                                    .frame(width: 28, height: 44)
                            }
                        }
                        .padding(.leading)

                        Spacer(minLength: 0)

                        Button(action: { showingCreateEvent = true }) {
                            Image(systemName: "plus")
                                .font(.body)
                                .foregroundColor(.blue)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Add event")
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 10)

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
                        Text("Tap '+' to add an event")
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

    private var isAllDay: Bool {
        guard let start = event.startDate, let end = event.endDate else { return false }
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        return (startComponents.hour == 0 && startComponents.minute == 0) &&
               (endComponents.hour == 0 && endComponents.minute == 0)
    }

    private var eventTimeDisplay: String {
        guard let start = event.startDate else { return "" }
        if isAllDay { return "All day" }
        guard let end = event.endDate else { return "" }
        let endText = compactEndTimeLabel(from: end)
        if let duration = durationLabel(from: start, to: end) {
            return "\(endText) (\(duration))"
        }
        return endText
    }

    /// Compact start time in the leading column (e.g. "6PM").
    private var compactStartTimeLabel: String? {
        guard let start = event.startDate, !isAllDay else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "ha"
        return formatter.string(from: start).uppercased()
    }

    private func compactEndTimeLabel(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).uppercased()
    }

    private func durationLabel(from start: Date, to end: Date) -> String? {
        let totalMinutes = Int(end.timeIntervalSince(start) / 60)
        guard totalMinutes > 0 else { return nil }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours) hr \(minutes) min"
        }
        if hours > 0 {
            return hours == 1 ? "1 hr" : "\(hours) hr"
        }
        return "\(minutes) min"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let compactStartTimeLabel {
                    Text(compactStartTimeLabel)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 2)
                } else {
                    Text(" ")
                        .font(.headline)
                        .hidden()
                        .padding(.horizontal, 2)
                }
            }
            .padding(.top, 5)
            .fixedSize()

            VStack(alignment: .leading, spacing: 5) {
                Text(event.name ?? "Untitled Event")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 5)

                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 14, alignment: .center)

                    Text(eventTimeDisplay)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let locationDisplay = eventLocationDisplay {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 14, alignment: .center)

                        Text(locationDisplay)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let uiImage = firstThumbnailImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Location title when set; otherwise the street line from `fullAddress`.
    private var eventLocationDisplay: String? {
        if let title = event.location?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        guard let fullAddress = event.fullAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !fullAddress.isEmpty else {
            return nil
        }

        if let street = fullAddress.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first {
            let trimmed = street.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return String(trimmed)
            }
        }

        return fullAddress
    }

    private var firstThumbnailImage: UIImage? {
        if let outfitsSet = event.outfits as? Set<Outfit> {
            for outfit in outfitsSet {
                if let imageData = outfit.image,
                   let uiImage = UIImage(data: imageData) {
                    return uiImage
                }
            }
        }

        if let itemsOrderedSet = event.items as? NSOrderedSet {
            for item in itemsOrderedSet.array as? [Item] ?? [] {
                if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                   let data = primaryPhoto.data,
                   let uiImage = UIImage(data: data) {
                    return uiImage
                }
            }
        }

        return nil
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
