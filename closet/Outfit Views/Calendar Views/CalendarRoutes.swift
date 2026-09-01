//
//  CalendarRoutes.swift
//  closet
//
//  Path entries for the calendar tab NavigationStack (Closet-style).
//

import Foundation
import Combine
import CoreLocation
import CoreData

/// Pushed on Calendar’s stack. Location and items are path values, not nested `item:` destinations.
enum CalendarRoute: Hashable {
    case eventDetail(String)
    case createEvent(id: UUID, initialDate: Date)
    /// Low-effort Outfit of the Day add (`OotdAddView`).
    case createOotd(id: UUID, initialDate: Date)
    case editEvent(String)
    case location
    case items(String)
    case itemsFilter
    case outfitsFilter
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

/// Shared by Event items/outfits selection and path-pushed wardrobe/filter screens.
final class EventItemsSelectionDraft: ObservableObject {
    @Published var selectedWardrobe: Wardrobe?
    let itemFilterModel = ItemFilterModel()
    let outfitFilterModel = OutfitFilterModel()
    let tabBarHideState = TabBarHideState()

    private var cancellables = Set<AnyCancellable>()

    init() {
        itemFilterModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        outfitFilterModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        tabBarHideState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
