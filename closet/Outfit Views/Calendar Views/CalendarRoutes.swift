//
//  CalendarRoutes.swift
//  closet
//
//  Path entries for the calendar tab NavigationStack (Closet-style).
//

import Foundation
import Combine
import CoreLocation

/// Pushed on Calendar’s stack. Location and items are path values, not nested `item:` destinations.
enum CalendarRoute: Hashable {
    case eventDetail(String)
    case createEvent(id: UUID, initialDate: Date)
    case editEvent(String)
    case location
    case items(String)
}

/// Shared by Event Add and path-pushed `LocationSearchView` (destinations do not inherit Event Add bindings).
final class EventLocationDraft: ObservableObject {
    @Published var selectedTitle: String?
    @Published var selectedSubtitle: String?
    @Published var selectedPlacemark: CLPlacemark?
    @Published var eventLocation: String = ""

    func reset() {
        selectedTitle = nil
        selectedSubtitle = nil
        selectedPlacemark = nil
        eventLocation = ""
    }
}
