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
    /// Open event detail on the calendar stack (caller dismisses this sheet, then pushes).
    let onSelectEvent: (Event) -> Void
    /// Create event on the calendar stack (caller dismisses this sheet, then pushes).
    let onCreateEvent: () -> Void

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    @FetchRequest private var events: FetchedResults<Event>

    init(
        selectedDate: Date,
        ownerUserId: String?,
        onDismiss: @escaping () -> Void,
        onNavigateDate: @escaping (Date) -> Void,
        onSelectEvent: @escaping (Event) -> Void,
        onCreateEvent: @escaping () -> Void
    ) {
        self.selectedDate = selectedDate
        self.ownerUserId = ownerUserId
        self.onDismiss = onDismiss
        self.onNavigateDate = onNavigateDate
        self.onSelectEvent = onSelectEvent
        self.onCreateEvent = onCreateEvent
        
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let request: NSFetchRequest<Event> = Event.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.startDate, ascending: true)]

        // Any event that occupies this calendar day (including multi-day spans).
        let overlapsDay = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "startDate < %@", endOfDay as NSDate),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "endDate >= %@", startOfDay as NSDate),
                NSPredicate(format: "endDate == nil AND startDate >= %@", startOfDay as NSDate),
            ]),
        ])
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        let userPredicate: NSPredicate
        if let uid = ownerUserId, !uid.isEmpty {
            userPredicate = NSPredicate(format: "userId == %@", uid)
        } else {
            userPredicate = NSPredicate(value: false)
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            overlapsDay, softDeleteFilter, userPredicate,
        ])

        _events = FetchRequest(fetchRequest: request)
    }

    /// Trip-linked day OOTDs are folded into the parent multi-day event row for this date.
    private var visibleEvents: [Event] {
        events.filter { !$0.isTripLinkedDayOOTD }
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

                        Button(action: { onCreateEvent() }) {
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
                if visibleEvents.isEmpty {
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
                        ForEach(visibleEvents, id: \.objectID) { event in
                            Button {
                                onSelectEvent(event)
                            } label: {
                                EventRowView(event: event, wardrobeDay: selectedDate)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let event = visibleEvents[index]
                                deleteEvent(event)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                Spacer()
            }
        }
        .background(
            Color(.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
    }

    private func navigateDate(_ direction: Int) {
        if let newDate = calendar.date(byAdding: .day, value: direction, to: selectedDate) {
            onNavigateDate(newDate)
        }
    }
    
    private func deleteEvent(_ event: Event) {
        withAnimation {
            softDelete(event)
            
            do {
                try viewContext.save()
                SyncService.shared.syncEventIfNeeded(event)
            } catch {
                print("Error deleting event: \(error)")
            }
        }
    }

}




// MARK: - Event Row View
struct EventRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    let event: Event
    /// Calendar day being viewed in the sheet; used to resolve per-day trip wardrobe thumbnails.
    var wardrobeDay: Date? = nil

    /// Fits widest compact start label (e.g. "12PM") so AM/PM columns align across rows.
    private static let startTimeColumnWidth: CGFloat = 52

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

    /// Compact start time in the leading column (e.g. "6PM"); all-day shows "ALL".
    /// OOTD uses a hanger icon instead (see `leadingTimeColumn`).
    private var compactStartTimeLabel: String? {
        guard event.startDate != nil else { return nil }
        if event.isOutfitOfTheDay { return nil }
        if isAllDay { return "ALL" }
        guard let start = event.startDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "ha"
        return formatter.string(from: start).uppercased()
    }

    /// Hide clock + "All day" when the leading column already conveys all-day (ALL / OOTD).
    private var showsTimeDetailRow: Bool {
        !isAllDay
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

    @ViewBuilder
    private var leadingTimeColumn: some View {
        Group {
            if event.isOutfitOfTheDay {
                Image(systemName: "hanger")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .accessibilityLabel("Outfit of the Day")
            } else {
                Text(compactStartTimeLabel ?? " ")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .opacity(compactStartTimeLabel == nil ? 0 : 1)
                    .accessibilityHidden(compactStartTimeLabel == nil)
            }
        }
        .multilineTextAlignment(.trailing)
        .frame(width: Self.startTimeColumnWidth, alignment: .trailing)
        .padding(.top, 5)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            leadingTimeColumn

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 6) {
                    if appCapabilities.enablesCloudSync {
                        Image(systemName: event.eventVisibility.iconName)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 14, alignment: .center)
                    }

                    Text(event.name ?? "Untitled Event")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 5)

                if showsTimeDetailRow {
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
        if let wardrobeDay,
           let dayImage = event.wardrobeThumbnailImage(for: wardrobeDay, in: viewContext) {
            return dayImage
        }
        return event.calendarThumbnailImage
    }
}



/*
// MARK: - Event Add View (legacy stub; real implementation is EventAddView.swift)
struct EventAddView: View {
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
