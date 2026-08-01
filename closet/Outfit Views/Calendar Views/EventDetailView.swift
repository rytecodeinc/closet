//
//  EventDetailView.swift
//  closet
//
//  Created by Dan Warner on 10/11/25.
//

import SwiftUI
import CoreData
import UIKit

struct EventDetailView: View {
    @ObservedObject var event: Event
    
    @State private var showingEditView = false
    @State private var showingMapOptions = false
    
    @Environment(\.managedObjectContext) private var viewContext
    
    private let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
    private let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    
    // Helper function to format time, hiding :00 when minutes are zero (e.g., "3:00 PM" -> "3 PM")
    private func formatTime(_ date: Date) -> String {
        let formatted = dateTimeFormatter.string(from: date)
        // Remove ":00" if present (handles both "3:00 PM" and "15:00" formats)
        return formatted.replacingOccurrences(of: ":00", with: "")
    }
    
    private var isAllDay: Bool {
        guard let start = event.startDate, let end = event.endDate else { return false }
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        return (startComponents.hour == 0 && startComponents.minute == 0) &&
               (endComponents.hour == 0 && endComponents.minute == 0)
    }
    
    // Computed property to get selected items array (preserves insertion order)
    private var selectedItems: [Item] {
        if let itemsOrderedSet = event.items as? NSOrderedSet {
            return itemsOrderedSet.array as? [Item] ?? []
        }
        return []
    }

    private var selectedOutfits: [Outfit] {
        guard let outfitsSet = event.outfits as? Set<Outfit> else { return [] }
        return outfitsSet.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    
    private var copyableLocationText: String? {
        let locationName = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fullAddress = event.fullAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !locationName.isEmpty, !fullAddress.isEmpty {
            return "\(locationName)\n\(fullAddress)"
        }
        if !fullAddress.isEmpty { return fullAddress }
        if !locationName.isEmpty { return locationName }
        return nil
    }

    private var hasEventLocation: Bool {
        guard let location = event.location?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty else { return false }
        return true
    }

    private var locationSection: some View {
        Group {
            if hasEventLocation {
                Button(action: presentLocationOptions) {
                    locationRowContent
                }
                .buttonStyle(.plain)
            } else {
                locationRowContent
            }
        }
    }

    private var locationRowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundColor(.gray)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .foregroundColor(.primary)
                } else {
                    Text("Location")
                        .foregroundColor(.secondary)
                }

                if let fullAddress = event.fullAddress, !fullAddress.isEmpty {
                    Text(fullAddress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var itemsSelectionSection: some View {
        EventItemsSelectionSection(items: selectedItems, outfits: selectedOutfits, isReadOnly: true) {}
    }

    // MARK: - Date & Time section

    private let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    private var isSameDayEvent: Bool {
        guard let start = event.startDate else { return false }
        guard let end = event.endDate else { return true }
        return Calendar.current.isDate(start, inSameDayAs: end)
    }

    /// Compact time like "6" / "7:30PM" — omits :00 minutes; AM/PM only when requested.
    private func compactTime(_ date: Date, includePeriod: Bool) -> String {
        let calendar = Calendar.current
        let hour24 = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        var text = "\(hour12)"
        if minute != 0 { text += String(format: ":%02d", minute) }
        if includePeriod { text += hour24 < 12 ? "AM" : "PM" }
        return text
    }

    /// "6-7:30PM" or "11AM-1:30PM" (start period shown only when it differs from end's).
    private func inlineTimeRange(start: Date, end: Date) -> String {
        let calendar = Calendar.current
        let samePeriod = (calendar.component(.hour, from: start) < 12) == (calendar.component(.hour, from: end) < 12)
        return "\(compactTime(start, includePeriod: !samePeriod))-\(compactTime(end, includePeriod: true))"
    }

    private var dateTimeSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock")
                .foregroundColor(.gray)
                .frame(width: 22)

            if isSameDayEvent, let startDate = event.startDate {
                Group {
                    if isAllDay {
                        Text("\(fullDateFormatter.string(from: startDate)) All-day")
                    } else if let endDate = event.endDate {
                        Text("\(fullDateFormatter.string(from: startDate)) \(inlineTimeRange(start: startDate, end: endDate))")
                    } else {
                        Text("\(fullDateFormatter.string(from: startDate)) \(compactTime(startDate, includePeriod: true))")
                    }
                }
                .font(.body)
            } else {
                VStack(alignment: .leading, spacing: 15) {
                    if isAllDay {
                        Text("All-day")
                            .font(.body)
                    }

                    if let startDate = event.startDate {
                        HStack {
                            Text("Start")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(isAllDay ? dateOnlyFormatter.string(from: startDate) : formatTime(startDate))
                        }
                    }

                    if let endDate = event.endDate {
                        HStack {
                            Text("End")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(isAllDay ? dateOnlyFormatter.string(from: endDate) : formatTime(endDate))
                        }
                    }
                }
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // MARK: - Event Name
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "calendar")
                        .foregroundColor(.gray)
                        .frame(width: 22)
                    Text(event.name ?? "Untitled Event")
                        .font(.title3)
                        .fontWeight(.medium)
                }
                .padding(.top, 4)
                .padding(.horizontal)

                // MARK: - Date & Time
                if event.startDate != nil || event.endDate != nil {
                    Divider()
                    dateTimeSection
                        .padding(.horizontal)
                }

                // MARK: - Location
                if hasEventLocation {
                    Divider()
                    locationSection
                        .padding(.horizontal)
                }

                // MARK: - Items Selection
                Divider()
                itemsSelectionSection
                    .padding(.horizontal)

                // MARK: - Notes/Description
                if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "note.text")
                            .foregroundColor(.gray)
                            .frame(width: 22)

                        Text(notes)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditView = true
                }
            }
        }
        .sheet(isPresented: $showingEditView) {
            CreateEventView(eventToEdit: event)
                .environment(\.managedObjectContext, viewContext)
        }
        .confirmationDialog("Event Location", isPresented: $showingMapOptions, titleVisibility: .visible) {
            Button("Copy to Clipboard") {
                copyLocationToClipboard()
            }
            if hasGoogleMaps() {
                Button("Open in Google Maps") {
                    openGoogleMaps()
                }
            }
            Button("Open in Maps") {
                openAppleMaps()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    // MARK: - Clipboard
    private func copyLocationToClipboard() {
        guard let text = copyableLocationText else { return }
        UIPasteboard.general.string = text
    }

    // MARK: - Map Functions
    private func presentLocationOptions() {
        showingMapOptions = true
    }

    private func hasGoogleMaps() -> Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    
    private func openAppleMaps() {
        if let address = mapsQueryAddress,
           let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "maps://?q=\(encodedAddress)") {
            UIApplication.shared.open(url)
            return
        }

        guard let latitude = event.latitude as Double?,
              let longitude = event.longitude as Double?,
              latitude != 0 || longitude != 0,
              let url = URL(string: "maps://?q=\(latitude),\(longitude)") else { return }
        UIApplication.shared.open(url)
    }

    private func openGoogleMaps() {
        if let address = mapsQueryAddress,
           let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "comgooglemaps://?q=\(encodedAddress)") {
            UIApplication.shared.open(url)
            return
        }

        guard let latitude = event.latitude as Double?,
              let longitude = event.longitude as Double?,
              latitude != 0 || longitude != 0,
              let url = URL(string: "comgooglemaps://?q=\(latitude),\(longitude)") else { return }
        UIApplication.shared.open(url)
    }

    private var mapsQueryAddress: String? {
        if let fullAddress = event.fullAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullAddress.isEmpty {
            return fullAddress
        }
        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            return location
        }
        return nil
    }
    
}
