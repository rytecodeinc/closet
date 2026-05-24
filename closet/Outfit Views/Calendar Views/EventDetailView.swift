//
//  EventDetailView.swift
//  closet
//
//  Created by Dan Warner on 10/11/25.
//

import SwiftUI
import CoreData
import CoreLocation
import MapKit

struct EventDetailView: View {
    @ObservedObject var event: Event
    private let imageSize: CGFloat = 100
    
    @State private var navigateToOutfits = false
    @State private var navigateToItems = false
    @State private var showingEditView = false
    @State private var showingMapOptions = false
    @State private var showingClearItemsConfirmation = false
    @State private var showingClearOutfitsConfirmation = false
    
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
    
    // Computed property to get selected items count
    private var selectedItemsCount: Int {
        if let itemsOrderedSet = event.items as? NSOrderedSet {
            return itemsOrderedSet.count
        }
        return 0
    }
    
    // Computed property to get selected items array (preserves insertion order)
    private var selectedItems: [Item] {
        if let itemsOrderedSet = event.items as? NSOrderedSet {
            return itemsOrderedSet.array as? [Item] ?? []
        }
        return []
    }
    
    // Computed property to get selected outfits count
    private var selectedOutfitsCount: Int {
        if let outfitsSet = event.outfits as? Set<Outfit> {
            return outfitsSet.count
        }
        return 0
    }
    
    // Computed property to get selected outfits array
    private var selectedOutfits: [Outfit] {
        if let outfitsSet = event.outfits as? Set<Outfit> {
            return Array(outfitsSet)
        }
        return []
    }

    private var hasEventLocation: Bool {
        guard let location = event.location?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty else { return false }
        return true
    }

    private var eventMapCoordinate: CLLocationCoordinate2D? {
        guard hasEventLocation,
              let latitude = event.latitude as Double?,
              let longitude = event.longitude as Double?,
              latitude != 0 || longitude != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
                Divider()
                
                // MARK: - Location
                HStack(spacing: 12) {
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
                .padding(.horizontal)
                Divider()
                
                // MARK: - Date & Time
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                            .frame(width: 22)
                            .padding(.top, 7)
                        
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
                .padding(.horizontal)
                Divider()
                
                // MARK: - Notes/Description
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundColor(.gray)
                        .frame(width: 22)
                    
                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                    } else {
                        Text("Notes")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                Divider()
                
                // MARK: - Items Selection
                ZStack {
                    Button(action: {
                        navigateToItems = true
                    }) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "tshirt")
                                .foregroundColor(.gray)
                                .frame(width: 22)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                if selectedItemsCount > 0 {
                                    Text("\(selectedItemsCount) item\(selectedItemsCount == 1 ? "" : "s") selected")
                                        .foregroundColor(.primary)
                                } else {
                                    Text("Add items from your closet")
                                        .foregroundColor(.secondary)
                                }
                                
                                // Selected Items Images
                                if selectedItemsCount > 0 {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(selectedItems, id: \.objectID) { item in
                                                if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                                                   let data = primaryPhoto.data,
                                                   let uiImage = UIImage(data: data) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .aspectRatio(1, contentMode: .fill)
                                                        .frame(width: 100, height: 100)
                                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                                } else if let imageData = item.image,
                                                          let uiImage = UIImage(data: imageData) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .aspectRatio(1, contentMode: .fill)
                                                        .frame(width: 100, height: 100)
                                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                                } else {
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(Color(.systemGray5))
                                                        .frame(width: 100, height: 100)
                                                        .overlay(
                                                            Image(systemName: "photo")
                                                                .foregroundColor(.secondary)
                                                                .font(.caption)
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Spacer()
                            
                            if selectedItemsCount == 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Clear button overlay (only when items are selected)
                    if selectedItemsCount > 0 {
                        HStack {
                            Spacer()
                            Button(action: {
                                showingClearItemsConfirmation = true
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                // MARK: - Outfits Selection
                ZStack {
                    Button(action: {
                        navigateToOutfits = true
                    }) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "photo.artframe")
                                .foregroundColor(.gray)
                                .frame(width: 22)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                if selectedOutfitsCount > 0 {
                                    Text("\(selectedOutfitsCount) outfit\(selectedOutfitsCount == 1 ? "" : "s") selected")
                                        .foregroundColor(.primary)
                                } else {
                                    Text("Add outfits")
                                        .foregroundColor(.secondary)
                                }
                                
                                // Selected Outfits Images
                                if selectedOutfitsCount > 0 {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(selectedOutfits, id: \.objectID) { outfit in
                                                if let imageData = outfit.image,
                                                   let uiImage = UIImage(data: imageData) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .aspectRatio(1, contentMode: .fill)
                                                        .frame(width: 100, height: 100)
                                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                                } else {
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(Color(.systemGray5))
                                                        .frame(width: 100, height: 100)
                                                        .overlay(
                                                            Image(systemName: "photo")
                                                                .foregroundColor(.secondary)
                                                                .font(.caption)
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Spacer()
                            
                            if selectedOutfitsCount == 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Clear button overlay (only when outfits are selected)
                    if selectedOutfitsCount > 0 {
                        HStack {
                            Spacer()
                            Button(action: {
                                showingClearOutfitsConfirmation = true
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                
                if let coordinate = eventMapCoordinate {
                    Divider()

                    // MARK: Map
                    Button(action: {
                        if hasGoogleMaps() {
                            showingMapOptions = true
                        } else {
                            openAppleMaps()
                        }
                    }) {
                        MapSnapshotView(coordinate: coordinate)
                            .frame(height: 150)
                            .clipped()
                    }
                    .buttonStyle(.plain)
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
        // MARK: Navigation destinations
        .navigationDestination(isPresented: $navigateToOutfits) {
            EventOutfitSelectionView(event: event)
                .environment(\.managedObjectContext, viewContext)
        }
        .navigationDestination(isPresented: $navigateToItems) {
            EventIndividualItemSelection(event: event)
                .environment(\.managedObjectContext, viewContext)
        }
        .confirmationDialog("Open in Maps", isPresented: $showingMapOptions, titleVisibility: .visible) {
            Group {
                if hasGoogleMaps() {
                    Button("Google Maps") {
                        openGoogleMaps()
                    }
                }
                Button("Maps") {
                    openAppleMaps()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .alert("Remove all items?", isPresented: $showingClearItemsConfirmation) {
            Button("Remove", role: .destructive) {
                clearAllItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove all items from this event?")
        }
        .alert("Remove all outfits?", isPresented: $showingClearOutfitsConfirmation) {
            Button("Remove", role: .destructive) {
                clearAllOutfits()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove all outfits from this event?")
        }
    }
    
    // MARK: - Clear Functions
    private func clearAllItems() {
        for item in selectedItems {
            event.removeFromItems(item)
        }
        do {
            try viewContext.save()
        } catch {
            print("Failed to clear items: \(error)")
        }
    }
    
    private func clearAllOutfits() {
        for outfit in selectedOutfits {
            event.removeFromOutfits(outfit)
        }
        do {
            try viewContext.save()
        } catch {
            print("Failed to clear outfits: \(error)")
        }
    }
    
    // MARK: - Map Functions
    private func hasGoogleMaps() -> Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    
    private func openAppleMaps() {
        guard let latitude = event.latitude as Double?,
              let longitude = event.longitude as Double? else { return }
        
        // Prefer address if available, otherwise use coordinates
        if let address = event.fullAddress ?? event.location, !address.isEmpty {
            // Use address query
            let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "maps://?q=\(encodedAddress)") {
                UIApplication.shared.open(url)
            }
        } else {
            // Use coordinates
            if let url = URL(string: "maps://?q=\(latitude),\(longitude)") {
                UIApplication.shared.open(url)
            }
        }
    }
    
    private func openGoogleMaps() {
        guard let latitude = event.latitude as Double?,
              let longitude = event.longitude as Double? else { return }
        
        // Prefer address if available, otherwise use coordinates
        if let address = event.fullAddress ?? event.location, !address.isEmpty {
            // Use address query
            let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "comgooglemaps://?q=\(encodedAddress)") {
                UIApplication.shared.open(url)
            }
        } else {
            // Use coordinates
            if let url = URL(string: "comgooglemaps://?q=\(latitude),\(longitude)") {
                UIApplication.shared.open(url)
            }
        }
    }
    
}

// MARK: Map Snapshot View
struct MapSnapshotView: View {
    let coordinate: CLLocationCoordinate2D
    @State private var snapshotImage: UIImage? = nil
    
    var body: some View {
        Group {
            if let image = snapshotImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
                    .onAppear { generateSnapshot() }
            }
        }
    }
    
    private func generateSnapshot() {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        options.size = CGSize(width: UIScreen.main.bounds.width - 32, height: 150)
        options.scale = UIScreen.main.scale
        
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            if let snapshot = snapshot {
                snapshotImage = snapshot.image
            } else if let error = error {
                print("Error generating map snapshot: \(error)")
            }
        }
    }
}
