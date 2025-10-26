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
    
    @State private var selectedTab = 0
    @State private var navigateToOutfits = false
    @State private var navigateToItems = false
    @State private var selectedEventForNavigation: Event? = nil
    
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                
                // MARK: Map
                if let latitude = event.latitude as Double?,
                   let longitude = event.longitude as Double? {
                    MapSnapshotView(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                        .frame(height: 200)
                    //     .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // MARK: Event Info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "calendar")
                            .frame(width: 40, alignment: .top)
                        
                        Text(event.name ?? "Untitled Event")
                            .font(.title)
                            .fontWeight(.bold)
                        
                    }
                    HStack{
                        Image(systemName: "clock")
                            .frame(width: 40, alignment: .top)
                        if let time = event.time {
                            Text("\(time, formatter: DateFormatter.eventDateTimeFormatter)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top) {
                        Image(systemName: "mappin.and.ellipse")
                            .frame(width: 40, alignment: .top)
                        VStack(alignment: .leading, spacing: 2) {
                            if let location = event.location, !location.isEmpty {
                                Text(location) // Regular font
                            }
                            if let fullAddress = event.fullAddress, !fullAddress.isEmpty {
                                Text(fullAddress)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // MARK: Tab Picker
                Picker("", selection: $selectedTab) {
                    Text("Outfits").tag(0)
                    Text("Items").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // MARK: Tab Content
                if selectedTab == 0 {
                    EventPickerView(
                        event: event,
                        type: .outfits,
                        imageSize: imageSize,
                        onAdd: {
                            selectedEventForNavigation = event
                            navigateToOutfits = true
                        }
                    )
                } else {
                    EventPickerView(
                        event: event,
                        type: .items,
                        imageSize: imageSize,
                        onAdd: {
                            selectedEventForNavigation = event
                            navigateToItems = true
                        }
                    )
                }
            
                
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        // MARK: Navigation destinations
        .navigationDestination(isPresented: $navigateToOutfits) {
            if let event = selectedEventForNavigation {
                EventOutfitSelectionView(event: event)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .navigationDestination(isPresented: $navigateToItems) {
            if let event = selectedEventForNavigation {
                EventIndividualItemSelection(event: event)
                    .environment(\.managedObjectContext, viewContext)
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
        options.size = CGSize(width: UIScreen.main.bounds.width - 32, height: 200)
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



extension DateFormatter {
    static let eventDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()
}
