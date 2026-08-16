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
    @Binding var navigationPath: NavigationPath
    
    @State private var showingMapOptions = false
    /// Bumped when returning from edit so notes/other fields re-render from Core Data.
    @State private var notesRefreshToken = UUID()
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    
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
        HStack(alignment: .top, spacing: 12) {
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

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var itemsSelectionSection: some View {
        EventItemsSelectionSection(items: selectedItems, outfits: selectedOutfits, isReadOnly: true) {}
    }

    private var displayedNotes: String? {
        let _ = notesRefreshToken
        let trimmed = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

            VStack(alignment: .leading, spacing: 2) {
                if let title = dateTimePrimaryLine {
                    Text(title)
                        .foregroundColor(.primary)
                }

                if let subtitle = dateTimeSecondaryLine {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Date line (location-style primary).
    private var dateTimePrimaryLine: String? {
        guard let startDate = event.startDate else { return nil }
        if isSameDayEvent {
            return fullDateFormatter.string(from: startDate)
        }
        guard let endDate = event.endDate else {
            return fullDateFormatter.string(from: startDate)
        }
        return "\(fullDateFormatter.string(from: startDate)) – \(fullDateFormatter.string(from: endDate))"
    }

    /// Start–end time (or All-day), location-style secondary.
    private var dateTimeSecondaryLine: String? {
        guard let startDate = event.startDate else { return nil }
        if isAllDay {
            return "All-day"
        }
        if isSameDayEvent {
            if let endDate = event.endDate {
                return inlineTimeRange(start: startDate, end: endDate)
            }
            return compactTime(startDate, includePeriod: true)
        }
        guard let endDate = event.endDate else {
            return compactTime(startDate, includePeriod: true)
        }
        return "\(compactTime(startDate, includePeriod: true)) – \(compactTime(endDate, includePeriod: true))"
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

                // MARK: - Privacy (cloud sync only)
                if appCapabilities.enablesCloudSync {
                    Divider()
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: event.eventVisibility.iconName)
                            .foregroundColor(.gray)
                            .frame(width: 22)
                        Text(event.eventVisibility.menuLabel)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                }

                // MARK: - Items Selection
                Divider()
                itemsSelectionSection
                    .padding(.horizontal)

                // MARK: - Notes/Description
                if let notes = displayedNotes {
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "note.text")
                            .foregroundColor(.gray)
                            .frame(width: 22)

                        Text(notes)
                            .font(.body)
                    }
                    .padding(.horizontal)
                    .id(notes)
                }
            }
            // Outside all rows — same visual clearance as ItemDetail history bottom pad.
            .padding(.bottom, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemBackground))
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    navigationPath.append(
                        CalendarRoute.editEvent(event.objectID.uriRepresentation().absoluteString)
                    )
                }
            }
        }
        .onChange(of: navigationPath.count) { _, _ in
            viewContext.refresh(event, mergeChanges: true)
            notesRefreshToken = UUID()
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
