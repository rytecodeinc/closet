//
//  OotdAddView.swift
//  closet
//
//  Low-effort Outfit of the Day add. Layout inspired by EventDetailLayoutPrototypeView;
//  only date, privacy, and outfit/items — no full event form.
//

import SwiftUI
import UIKit
import CoreData

struct OotdAddView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession

    let eventToEdit: Event?
    @Binding var navigationPath: NavigationPath

    @State private var selectedDate: Date
    @State private var visibility: WardrobeVisibility = .private
    @State private var isWhenExpanded = true
    @State private var isWhoExpanded = true
    @State private var isWardrobeExpanded = true
    @State private var draftEvent: Event?
    @State private var refreshToken = UUID()
    @State private var heroSegment: SocialEngagementToolbarSegment = .tshirt
    @State private var showDiscardAlert = false
    @State private var showSaveAsOutfitAlert = false
    @State private var didCaptureBaseline = false
    @State private var baselineDate: Date = Date()
    @State private var baselineVisibility: WardrobeVisibility = .private
    @State private var baselineItems: [Item] = []
    @State private var baselineOutfits: [Outfit] = []

    init(
        eventToEdit: Event? = nil,
        initialDate: Date = Date(),
        navigationPath: Binding<NavigationPath>
    ) {
        self.eventToEdit = eventToEdit
        _navigationPath = navigationPath
        if let event = eventToEdit {
            let day = Calendar.current.startOfDay(for: event.startDate ?? event.date ?? initialDate)
            _selectedDate = State(initialValue: day)
            _visibility = State(initialValue: event.eventVisibility)
            _draftEvent = State(initialValue: event)
        } else {
            let day = Calendar.current.startOfDay(for: initialDate)
            _selectedDate = State(initialValue: day)
        }
    }

    private var calendarAccountUserId: String? {
        authSession.userId?.uuidString
    }

    private var selectedItems: [Item] {
        guard let event = draftEvent,
              let ordered = event.items as? NSOrderedSet else { return [] }
        return ordered.array as? [Item] ?? []
    }

    private var selectedOutfits: [Outfit] {
        guard let event = draftEvent,
              let set = event.outfits as? Set<Outfit> else { return [] }
        return set.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var hasSelection: Bool {
        !selectedItems.isEmpty || !selectedOutfits.isEmpty
    }

    private var canSave: Bool {
        hasSelection
    }

    private var hasUnsavedChanges: Bool {
        if !Calendar.current.isDate(selectedDate, inSameDayAs: baselineDate) { return true }
        if visibility != baselineVisibility { return true }
        if selectedItems.map(\.objectID) != baselineItems.map(\.objectID) { return true }
        if Set(selectedOutfits.map(\.objectID)) != Set(baselineOutfits.map(\.objectID)) { return true }
        return false
    }

    private var isEditingExisting: Bool {
        eventToEdit != nil
    }

    private var attributeRowInsets: EdgeInsets {
        EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)
    }

    var body: some View {
        List {
            Section {
                if isWardrobeExpanded {
                    outfitHeroRow
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    heroEngagementRow
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            } header: {
                sectionHeader("WARDROBE", isExpanded: $isWardrobeExpanded)
            }
            .listSectionSpacing(0)

            if appCapabilities.enablesCloudSync {
                Section {
                    if isWhoExpanded {
                        privacyRow
                    }
                } header: {
                    sectionHeader("WHO", isExpanded: $isWhoExpanded)
                }
                .listSectionSpacing(4)
            }

            Section {
                if isWhenExpanded {
                    DatePicker(
                        "Date",
                        selection: $selectedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .listRowInsets(attributeRowInsets)
                    .listRowSeparator(.hidden)
                }
            } header: {
                sectionHeader("WHEN", isExpanded: $isWhenExpanded)
            }
            .listSectionSpacing(4)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .id(refreshToken)
        .background(Color(.systemBackground))
        .navigationTitle("Outfit of the Day")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: attemptDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(hasUnsavedChanges ? "Cancel" : "Back")
                    }
                }
                .accessibilityLabel(hasUnsavedChanges ? "Cancel" : "Back")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save", action: attemptSave)
                    .disabled(!canSave)
            }
        }
        .alert(
            isEditingExisting ? "Discard Changes?" : "Discard Outfit of the Day?",
            isPresented: $showDiscardAlert
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) {
                discardAndDismiss(discardingChanges: true)
            }
        } message: {
            Text(
                isEditingExisting
                    ? "You have unsaved edits. Going back will discard them."
                    : "You have unsaved changes. Going back will discard them."
            )
        }
        .alert("Save Wardrobe", isPresented: $showSaveAsOutfitAlert) {
            Button("Save as Items") {
                commitSave(saveMultipleAsOutfit: false)
            }
            Button("Save as Outfit") {
                commitSave(saveMultipleAsOutfit: true)
            }
        } message: {
            Text("You selected multiple items. Save them as individual items on this outfit of the day, or combine them into an outfit in your closet.")
        }
        .onAppear {
            guard !didCaptureBaseline else { return }
            baselineDate = selectedDate
            baselineVisibility = visibility
            baselineItems = selectedItems
            baselineOutfits = selectedOutfits
            didCaptureBaseline = true
        }
        .onChange(of: navigationPath.count) { _, _ in
            refreshToken = UUID()
            if let event = draftEvent {
                viewContext.refresh(event, mergeChanges: true)
            }
        }
    }

    // MARK: - Rows

    private var outfitHeroRow: some View {
        Button(action: openItemsSelection) {
            Color(.systemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay { heroOverlayContent }
                .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasSelection ? "Edit outfit of the day" : "Add outfit of the day")
    }

    @ViewBuilder
    private var heroOverlayContent: some View {
        switch heroSegment {
        case .tshirt:
            if hasSelection {
                EventSelectedItemsDisplayArea(
                    thumbnails: selectedOutfits.map { .outfit($0) }
                        + selectedItems.map { .item($0) },
                    fillsEdgeToEdge: true
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Tap to add items or outfits")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            }
        case .worn:
            if let wornImage = firstWornHeroImage {
                Image(uiImage: wornImage)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.square.badge.camera")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No worn photo")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var heroEngagementRow: some View {
        SocialEngagementActionsRow(
            segmentSelection: $heroSegment,
            showsLikeButton: false,
            showsCalendarButton: false,
            showsShareButton: false,
            showsWornSegment: true,
            disabledSegments: hasSelection ? [] : [.worn]
        )
        .onChange(of: hasSelection) { _, hasItemsOrOutfits in
            if !hasItemsOrOutfits, heroSegment == .worn {
                heroSegment = .tshirt
            }
        }
    }

    private var firstWornHeroImage: UIImage? {
        for outfit in selectedOutfits {
            if let data = outfit.wornImage, let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    private var privacyRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: visibility.iconName)
                .foregroundColor(.gray)
                .frame(width: 22)
            Picker("Privacy", selection: $visibility) {
                ForEach(WardrobeVisibility.allCases) { value in
                    Text(value.menuLabel).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer(minLength: 0)
            if visibility == .private {
                Text("Only Me")
                    .foregroundStyle(.secondary)
            }
        }
        .listRowInsets(attributeRowInsets)
        .listRowSeparator(.hidden)
    }

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
            Spacer()
            Image(systemName: isExpanded.wrappedValue ? "minus" : "plus")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.wrappedValue.toggle()
            }
        }
    }

    // MARK: - Actions

    private func attemptDismiss() {
        if hasUnsavedChanges {
            showDiscardAlert = true
        } else {
            discardAndDismiss(discardingChanges: false)
        }
    }

    private func discardAndDismiss(discardingChanges: Bool) {
        if let event = eventToEdit {
            if discardingChanges {
                restoreFromBaseline(event)
            }
            dismiss()
            return
        }

        // New OOTD: remove any draft row created during this session.
        if let event = draftEvent {
            if event.objectID.isTemporaryID {
                viewContext.delete(event)
            } else {
                softDelete(event)
                do {
                    try viewContext.save()
                    SyncService.shared.syncEventIfNeeded(event)
                } catch {
                    print("Error discarding OOTD draft: \(error)")
                }
            }
        }
        dismiss()
    }

    private func restoreFromBaseline(_ event: Event) {
        applyAllDayDates(to: event, date: baselineDate)
        event.eventVisibility = baselineVisibility
        event.name = Event.ootdDisplayName
        event.theme = Event.ootdThemeMarker

        if let existingItems = event.items as? NSOrderedSet {
            event.removeFromItems(existingItems)
        }
        for item in baselineItems {
            event.addToItems(item)
        }

        if let existingOutfits = event.outfits as? Set<Outfit> {
            for outfit in existingOutfits {
                event.removeFromOutfits(outfit)
            }
        }
        for outfit in baselineOutfits {
            event.addToOutfits(outfit)
        }

        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
            SyncService.shared.syncEventIfNeeded(event)
        } catch {
            print("Error restoring OOTD after discard: \(error)")
        }
    }

    private func openItemsSelection() {
        ensureDraftEvent()
        guard let event = draftEvent else { return }
        if event.objectID.isTemporaryID {
            do {
                try viewContext.obtainPermanentIDs(for: [event])
            } catch {
                print("Error obtaining permanent ID for OOTD before items selection: \(error)")
                return
            }
        }
        navigationPath.append(CalendarRoute.items(event.objectID.uriRepresentation().absoluteString))
    }

    private func ensureDraftEvent() {
        if draftEvent == nil {
            let event = Event(context: viewContext)
            event.id = UUID()
            event.userId = calendarAccountUserId
            event.eventVisibility = visibility
            applyAllDayDates(to: event)
            event.name = Event.ootdDisplayName
            event.theme = Event.ootdThemeMarker
            event.timestamp = Date()
            setCreatedAndUpdatedAt(event)
            draftEvent = event
        } else {
            updateDraftEvent()
        }
    }

    private func updateDraftEvent() {
        guard let event = draftEvent else { return }
        applyAllDayDates(to: event)
        event.eventVisibility = visibility
        event.name = Event.ootdDisplayName
        event.theme = Event.ootdThemeMarker
    }

    private func applyAllDayDates(to event: Event, date: Date? = nil) {
        let day = Calendar.current.startOfDay(for: date ?? selectedDate)
        event.startDate = day
        event.endDate = day
        event.date = day
    }

    private func attemptSave() {
        guard canSave else { return }
        ensureDraftEvent()
        guard let event = draftEvent else { return }
        if EventTripDayWardrobe.shouldPromptSaveLooseItemsAsOutfit(on: event) {
            showSaveAsOutfitAlert = true
            return
        }
        commitSave(saveMultipleAsOutfit: nil)
    }

    private func commitSave(saveMultipleAsOutfit: Bool?) {
        guard canSave else { return }
        ensureDraftEvent()
        guard let event = draftEvent else { return }

        applyAllDayDates(to: event)
        event.name = Event.ootdDisplayName
        event.theme = Event.ootdThemeMarker
        event.eventVisibility = visibility
        if (event.userId == nil || (event.userId ?? "").isEmpty), let uid = calendarAccountUserId {
            event.userId = uid
        }
        if event.createdAt == nil {
            setCreatedAndUpdatedAt(event)
        } else {
            setUpdatedAt(event)
        }

        var newlyCreatedOutfit: Outfit?
        if EventTripDayWardrobe.shouldMaterializeLooseItemsOnSave(
            on: event,
            saveMultipleAsOutfit: saveMultipleAsOutfit
        ) {
            newlyCreatedOutfit = EventTripDayWardrobe.materializeLooseItemsIfNeeded(
                on: event,
                userId: event.userId ?? calendarAccountUserId,
                in: viewContext
            )
        }

        do {
            try viewContext.save()
            if let outfit = newlyCreatedOutfit {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            SyncService.shared.syncEventIfNeeded(event)
            dismiss()
        } catch {
            print("Error saving Outfit of the Day: \(error)")
        }
    }
}

extension Event {
    static let ootdDisplayName = "Outfit of the Day"
    static let ootdThemeMarker = "ootd"

    var isOutfitOfTheDay: Bool {
        let trimmedTheme = (theme ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmedTheme == Self.ootdThemeMarker { return true }
        // Trip-linked day OOTDs use "ootd:<parentEventUUID>"
        if trimmedTheme.hasPrefix("\(Self.ootdThemeMarker):") { return true }

        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.caseInsensitiveCompare(Self.ootdDisplayName) == .orderedSame { return true }
        // Short / legacy labels
        return trimmedName.caseInsensitiveCompare("OOTD") == .orderedSame
    }

    /// First outfit/item image for calendar OOTD squares and drawer previews.
    var calendarThumbnailImage: UIImage? {
        if let outfitsSet = outfits as? Set<Outfit> {
            for outfit in outfitsSet {
                if let imageData = outfit.image,
                   let uiImage = UIImage(data: imageData) {
                    return uiImage
                }
            }
        }

        if let itemsOrderedSet = items as? NSOrderedSet {
            for item in itemsOrderedSet.array as? [Item] ?? [] {
                if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                   let data = primaryPhoto.data,
                   let uiImage = UIImage(data: data) {
                    return uiImage
                }
                if let imageData = item.image,
                   let uiImage = UIImage(data: imageData) {
                    return uiImage
                }
            }
        }

        return nil
    }

    /// Primary outfit for OOTD full-screen preview (newest with collage when multiple).
    var primaryOotdOutfit: Outfit? {
        guard let outfitsSet = outfits as? Set<Outfit> else { return nil }
        return outfitsSet.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.first
    }

    /// Collage slot for `OutfitFullScreenView` — outfit image, else first item/outfit thumb.
    var ootdFullScreenCollageImage: UIImage? {
        if let outfit = primaryOotdOutfit,
           let imageData = outfit.image,
           let uiImage = UIImage(data: imageData) {
            return uiImage
        }
        return calendarThumbnailImage
    }

    /// Worn slot for `OutfitFullScreenView` from any linked outfit.
    var ootdFullScreenWornImage: UIImage? {
        guard let outfitsSet = outfits as? Set<Outfit> else { return nil }
        for outfit in outfitsSet {
            if let imageData = outfit.wornImage,
               let uiImage = UIImage(data: imageData) {
                return uiImage
            }
        }
        return nil
    }
}
