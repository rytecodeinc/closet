//
//  EventAddView.swift
//  closet
//
//  Created by Dan Warner on 10/11/25.
//

import SwiftUI
import MapKit
import Combine
import Contacts
import CoreData
import UIKit

struct EventAddView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var locationDraft: EventLocationDraft

    @FetchRequest(
        entity: UserProfile.entity(),
        sortDescriptors: []
    ) private var allUserProfiles: FetchedResults<UserProfile>
    
    let eventToEdit: Event?
    @Binding var navigationPath: NavigationPath
    
    /// Account that owns new calendar rows (matches `Event.userId` filtering elsewhere).
    private var calendarAccountUserId: String? {
        authSession.userId?.uuidString
    }
    
    @State private var eventName = ""
    @State private var eventTheme = ""
    @State private var eventOccasion = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var eventNotes = ""
    @State private var isAllDay = false
    @State private var eventVisibility: WardrobeVisibility = .private
    
    @State private var tempEvent: Event?
    @State private var refreshToken = UUID() // Force view refresh when items change
    @State private var isWhoExpanded = false
    @State private var isWhatExpanded = true
    @State private var isWhenExpanded = true
    @State private var isWhereExpanded = false
    @State private var isWardrobeExpanded = true
    @State private var activeFieldSheet: EventAddFieldSheet?
    @State private var heroSegment: SocialEngagementToolbarSegment = .tshirt
    /// Multi-day all-day: focused day in WARDROBE.
    @State private var wardrobeDayIndex = 0
    /// Grid = up to 4 at a glance; off = one large hero (current).
    @State private var isWardrobeGridLayout = false
    @State private var sessionCreatedDayOOTDObjectIDs: Set<NSManagedObjectID> = []
    @State private var originalDayWardrobeFingerprints: [TimeInterval: String] = [:]
    @State private var dayOOTDDiscardSnapshots: [DayOOTDDiscardSnapshot] = []
    
    @State private var showDiscardAlert = false
    @State private var showSaveAsOutfitAlert = false
    @State private var showCopiedAddressToast = false
    @State private var dateTimeSheetDidCommit = false
    @State private var pendingDateRemapDecision: EventDateRemapDecision?
    @State private var didCaptureOriginals = false
    /// Calendar range day OOTDs are currently keyed to (may differ from start/end after Keep Dates).
    @State private var wardrobeAlignedStart: Date
    @State private var wardrobeAlignedEnd: Date
    @State private var dateEditBaselineStart: Date?
    @State private var dateEditBaselineEnd: Date?
    @State private var dateEditOpenedSheet: EventAddFieldSheet?
    @State private var originalName = ""
    @State private var originalTheme = ""
    @State private var originalOccasion = ""
    @State private var originalLocation = ""
    @State private var originalNotes = ""
    @State private var originalStartDate = Date()
    @State private var originalEndDate = Date()
    @State private var originalIsAllDay = false
    @State private var originalVisibility: WardrobeVisibility = .private
    @State private var originalLatitude: Double = 0
    @State private var originalLongitude: Double = 0
    @State private var originalFullAddress: String? = nil
    @State private var originalItems: [Item] = []
    @State private var originalOutfits: [Outfit] = []
    @State private var showParticipantsSheet = false
    @State private var eventParticipants: [EventParticipantRecord] = []
    
    // Computed property to get selected items array (preserves insertion order)
    /// Multi-day events (all-day or timed) use per-day linked OOTDs for wardrobe.
    private var usesPerDayWardrobe: Bool {
        dateSpansMultipleDays
    }

    private var tripWardrobeDays: [Date] {
        EventTripDayWardrobe.days(from: startDate, to: endDate)
    }

    private var focusedTripDay: Date {
        let days = tripWardrobeDays
        guard !days.isEmpty else { return Calendar.current.startOfDay(for: startDate) }
        let idx = min(max(wardrobeDayIndex, 0), days.count - 1)
        return days[idx]
    }

    /// Event whose items/outfits the WARDROBE hero edits (trip day OOTD or the event itself).
    private var wardrobeSourceEvent: Event? {
        if usesPerDayWardrobe {
            guard let parent = tempEvent,
                  let parentId = parent.id,
                  let userId = parent.userId ?? calendarAccountUserId else { return nil }
            return EventTripDayWardrobe.findDayOOTD(
                parentEventId: parentId,
                day: focusedTripDay,
                userId: userId,
                in: viewContext
            )
        }
        return tempEvent
    }

    private var selectedItems: [Item] {
        guard let event = wardrobeSourceEvent,
              let itemsOrderedSet = event.items as? NSOrderedSet else { return [] }
        return itemsOrderedSet.array as? [Item] ?? []
    }

    private var selectedOutfits: [Outfit] {
        guard let event = wardrobeSourceEvent,
              let outfitsSet = event.outfits as? Set<Outfit> else { return [] }
        return outfitsSet.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    

    private var currentUserProfile: UserProfile? {
        guard let userId = calendarAccountUserId else { return nil }
        return allUserProfiles.first { $0.userId == userId }
    }

    private var currentUserAvatarProfile: PublicUserProfile? {
        guard let uid = authSession.userId else { return nil }
        return PublicUserProfile(
            userId: uid,
            username: currentUserProfile?.username ?? supabaseService.cachedUsername ?? "",
            displayName: currentUserProfile?.displayName,
            avatarUrl: currentUserProfile?.storedProfileAvatarURL
        )
    }

    private var eventParticipantGuestRecords: [EventParticipantRecord] {
        eventParticipants.filter {
            $0.role != "host" && ($0.status == "pending" || $0.status == "accepted")
        }
    }

    private var isOnlyOwnUserParticipant: Bool {
        eventParticipantGuestRecords.isEmpty
    }

    @ViewBuilder
    private var whoParticipantRows: some View {
        if let host = currentUserAvatarProfile {
            EventParticipantRow(
                profile: host,
                statusLabel: isOnlyOwnUserParticipant ? "Only You" : "You"
            )
            .listRowInsets(attributeRowInsets)
            .listRowSeparator(.hidden)
        }

        ForEach(eventParticipantGuestRecords) { participant in
            EventParticipantRow(
                profile: participant.publicProfile,
                statusLabel: participant.statusLabel ?? "Invited"
            )
            .listRowInsets(attributeRowInsets)
            .listRowSeparator(.hidden)
        }
    }

    private var inviteParticipantsRow: some View {
        Button {
            showParticipantsSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .foregroundColor(.gray)
                    .frame(width: 22)
                Text("Invite")
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(attributeRowInsets)
        .listRowSeparator(.hidden)
        .accessibilityLabel("Invites")
    }

    init(
        eventToEdit: Event? = nil,
        initialDate: Date = Date(),
        navigationPath: Binding<NavigationPath>
    ) {
        self.eventToEdit = eventToEdit
        self._navigationPath = navigationPath
        if let event = eventToEdit {
            _startDate = State(initialValue: event.startDate ?? initialDate)
            _endDate = State(initialValue: event.endDate ?? initialDate.addingTimeInterval(3600))
            _wardrobeAlignedStart = State(initialValue: event.startDate ?? initialDate)
            _wardrobeAlignedEnd = State(initialValue: event.endDate ?? initialDate.addingTimeInterval(3600))
        } else {
            _startDate = State(initialValue: initialDate)
            _endDate = State(initialValue: initialDate.addingTimeInterval(3600))
            _wardrobeAlignedStart = State(initialValue: initialDate)
            _wardrobeAlignedEnd = State(initialValue: initialDate.addingTimeInterval(3600))
        }
    }
    
    var body: some View {
                createEventForm
            .onChange(of: navigationPath.count) { _, _ in
                refreshToken = UUID()
                refreshWardrobeEventsFromStore()
        }
    }
    
    private var createEventForm: some View {
        List {
            Section {
                if isWardrobeExpanded {
                    if usesPerDayWardrobe {
                        wardrobeDaySwitcherRow
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                    itemsHeroRow
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
                        inviteParticipantsRow
                        whoParticipantRows
                    }
                } header: {
                    sectionHeader("WHO", isExpanded: $isWhoExpanded)
                }
                .listSectionSpacing(4)
            }

            Section {
                if isWhatExpanded {
                    chevronFieldRow(
                        label: "Name",
                        value: nameRowValue,
                        opens: .name
                    )
                    chevronFieldRow(
                        label: "Occasion",
                        value: occasionRowValue,
                        opens: .occasion
                    )
                    chevronFieldRow(
                        label: "Theme",
                        value: themeRowValue,
                        opens: .theme
                    )
                    chevronFieldRow(
                        label: "Notes",
                        value: notesRowValue,
                        allowsMultiline: true,
                        opens: .notes
                    )
                }
            } header: {
                sectionHeader("WHAT", isExpanded: $isWhatExpanded)
            }
            .listSectionSpacing(4)

            Section {
                if isWhenExpanded {
                    chevronFieldRow(
                        label: "Date & Time",
                        value: dateTimeRowValue,
                        caption: isAllDay ? "All-day" : nil,
                        allowsMultiline: !isAllDay,
                        preventsLabelWrapping: true,
                        opens: .dateAndTime
                    )
                }
            } header: {
                sectionHeader("WHEN", isExpanded: $isWhenExpanded)
            }
            .listSectionSpacing(4)

            Section {
                if isWhereExpanded {
                    chevronFieldRow(
                        label: "Location",
                        value: locationRowValue,
                        caption: locationRowCaption,
                        opens: .location
                    )
                    if hasLocationForShare {
                        EventLocationShareActionsRow(
                            shareText: locationShareText,
                            mapsQueryAddress: locationMapsQueryAddress,
                            latitude: locationShareLatitude,
                            longitude: locationShareLongitude,
                            rowInsets: attributeRowInsets,
                            onCopiedAddress: presentCopiedAddressToast
                        )
                    }
                }
                whereSectionBottomPad
            } header: {
                sectionHeader("WHERE", isExpanded: $isWhereExpanded)
            }
            .listSectionSpacing(4)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .id(refreshToken)
            .background(Color(.systemBackground))
            .navigationTitle(eventToEdit == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .onAppear {
                guard !didCaptureOriginals else { return }
                if let event = eventToEdit {
                    loadEventForEditing(event)
                    tempEvent = event // Use existing event when editing
                }
                // Don't create temp event here - only create when needed (navigation or save)
                captureOriginals()
                didCaptureOriginals = true
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: attemptCancel) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(hasUnsavedChanges ? "Cancel" : "Back")
                        }
                    }
                    .accessibilityLabel(hasUnsavedChanges ? "Cancel" : "Back")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: attemptSaveEvent)
                        .disabled(!canSaveEvent || !hasUnsavedChanges)
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) {
                    cancelEditing(discardingChanges: true)
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved edits. Going back will discard them.")
            }
            .alert("Save Wardrobe", isPresented: $showSaveAsOutfitAlert) {
                Button("Save as Items") {
                    commitSaveEvent(saveMultipleAsOutfit: false)
                }
                Button("Save as Outfit") {
                    commitSaveEvent(saveMultipleAsOutfit: true)
                }
            } message: {
                Text("You selected multiple items. Save them as individual items on this event, or combine them into an outfit in your closet.")
            }
            .sheet(isPresented: $showParticipantsSheet) {
                EventParticipantsSheet(
                    hostProfile: currentUserAvatarProfile,
                    eventName: eventName,
                    participants: $eventParticipants,
                    onEnsureEventSaved: ensureEventSavedForInvite
                )
            }

            .sheet(item: $activeFieldSheet, onDismiss: {
                handleDateRangeEditDismissIfNeeded()
            }) { sheet in
                eventFieldSheet(for: sheet)
                    .presentationDetents(presentationDetents(for: sheet))
            }
            .task(id: (eventToEdit ?? tempEvent)?.id) {
                await loadEventParticipants()
            }
            .overlay(alignment: .top) {
                if showCopiedAddressToast {
                    Text("Copied address to clipboard")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
    }

    private func presentCopiedAddressToast() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showCopiedAddressToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.22)) {
                showCopiedAddressToast = false
            }
        }
    }
    

    private var attributeRowInsets: EdgeInsets {
        EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)
    }

    private var whereSectionBottomPad: some View {
        Color.clear
            .frame(height: 4)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .environment(\.defaultMinListRowHeight, 1)
    }

    private var hasSelection: Bool {
        !selectedItems.isEmpty || !selectedOutfits.isEmpty
    }

    private var itemsHeroRow: some View {
        Color(.systemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay { heroOverlayContent }
            .clipped()
            .accessibilityLabel(itemsHeroAccessibilityLabel)
            // Keep hit-testing off the outer control in multi-day grid so day cells receive taps,
            // but do not use `.disabled` — that greys out filled outfit thumbnails.
            .allowsHitTesting(!(isWardrobeGridLayout && usesPerDayWardrobe))
    }

    private var itemsHeroAccessibilityLabel: String {
        if usesPerDayWardrobe {
            if isWardrobeGridLayout {
                return "Trip day outfits at a glance"
            }
            return hasSelection ? "Edit outfit for selected day" : "Add outfit for selected day"
        }
        return hasSelection ? "Edit items and outfits" : "Add items and outfits"
    }

    @ViewBuilder
    private var heroOverlayContent: some View {
        if usesPerDayWardrobe && isWardrobeGridLayout {
            tripDayGridOverlay
        } else if !usesPerDayWardrobe && isWardrobeGridLayout {
            selectionGridOverlay
        } else if heroDisabledSegments.contains(.worn) {
            // No swipe while worn is disabled (empty wardrobe).
            itemsHeroPage
                                        } else {
            TabView(selection: $heroSegment) {
                itemsHeroPage
                    .tag(SocialEngagementToolbarSegment.tshirt)
                wornHeroPage
                    .tag(SocialEngagementToolbarSegment.worn)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private var itemsHeroPage: some View {
        Group {
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
                    Text(usesPerDayWardrobe ? "Tap to add outfit for this day" : "Tap to add items or outfits")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { openItemsSelection() }
    }

    private var wornHeroPage: some View {
        Group {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// 2×2 of trip days (page of 4) for at-a-glance OOTD coverage.
    private var tripDayGridOverlay: some View {
        let days = tripWardrobeDays
        let pageStart = (wardrobeDayIndex / 4) * 4
        let pageDays = Array(days.dropFirst(pageStart).prefix(4))
        let cells: [Date?] = pageDays + Array(repeating: nil, count: max(0, 4 - pageDays.count))
        return ZStack {
            Color(.systemBackground)
            VStack(spacing: 1) {
            HStack(spacing: 1) {
                tripDayGridCell(day: cells[0], index: pageStart)
                tripDayGridCell(day: cells[1], index: pageStart + 1)
            }
            HStack(spacing: 1) {
                tripDayGridCell(day: cells[2], index: pageStart + 2)
                tripDayGridCell(day: cells[3], index: pageStart + 3)
            }
            }
        }
    }

    @ViewBuilder
    private func tripDayGridCell(day: Date?, index: Int) -> some View {
        let isActive = day != nil && index < tripWardrobeDays.count
        Button {
            guard isActive else { return }
            wardrobeDayIndex = index
            isWardrobeGridLayout = false
        } label: {
            ZStack {
                if let day {
                    let ootd = dayOOTDIfPresent(for: day)
                    let thumbs = EventTripDayWardrobe.thumbnails(for: ootd)
                    if !thumbs.isEmpty {
                        Color(.systemBackground)
                        EventSelectedItemsDisplayArea(thumbnails: Array(thumbs.prefix(4)), fillsEdgeToEdge: true)
                                        } else {
                        Color(.secondarySystemBackground)
                        Image(systemName: "plus")
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Spacer()
                        Text(shortDayLabel(day))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
                } else {
                    Color(.secondarySystemBackground).opacity(0.35)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        // Prefer hit-testing over `.disabled` so filled day cells never inherit a greyed look.
        .allowsHitTesting(isActive)
    }

    /// Single-event wardrobe: force a 2×2 of up to four selection thumbnails.
    private var selectionGridOverlay: some View {
        let thumbs = (selectedOutfits.map { EventSelectedThumbnail.outfit($0) }
            + selectedItems.map { EventSelectedThumbnail.item($0) })
        let padded: [EventSelectedThumbnail?] = {
            let prefix = Array(thumbs.prefix(4))
            return prefix + Array(repeating: nil, count: max(0, 4 - prefix.count))
        }()
        return ZStack {
            Color(.systemBackground)
            VStack(spacing: 1) {
            HStack(spacing: 1) {
                selectionGridCell(padded[0])
                selectionGridCell(padded[1])
            }
            HStack(spacing: 1) {
                selectionGridCell(padded[2])
                selectionGridCell(padded[3])
            }
            }
        }
    }

    @ViewBuilder
    private func selectionGridCell(_ thumb: EventSelectedThumbnail?) -> some View {
        ZStack {
            if let thumb {
                Color(.systemBackground)
                EventSelectedItemsDisplayArea(thumbnails: [thumb], fillsEdgeToEdge: true)
            } else if !hasSelection {
                Color(.secondarySystemBackground)
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
            } else {
                Color(.systemBackground)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var wardrobePageSize: Int { 4 }

    private var wardrobePageCount: Int {
        let dayCount = tripWardrobeDays.count
        guard dayCount > 0 else { return 1 }
        return Int(ceil(Double(dayCount) / Double(wardrobePageSize)))
    }

    private var wardrobePageIndex: Int {
        guard !tripWardrobeDays.isEmpty else { return 0 }
        return min(wardrobeDayIndex / wardrobePageSize, wardrobePageCount - 1)
    }

    private var wardrobeSwitcherShowsPageArrows: Bool {
        isWardrobeGridLayout && tripWardrobeDays.count > wardrobePageSize
    }

    private var wardrobeDaySwitcherRow: some View {
        HStack {
            wardrobeSwitcherChevron(
                systemName: "chevron.left",
                visible: isWardrobeGridLayout
                    ? (wardrobeSwitcherShowsPageArrows && wardrobePageIndex > 0)
                    : wardrobeDayIndex > 0
            ) {
                if isWardrobeGridLayout {
                    wardrobeDayIndex = max(0, (wardrobePageIndex - 1) * wardrobePageSize)
                } else {
                    wardrobeDayIndex = max(0, wardrobeDayIndex - 1)
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text(wardrobeSwitcherTitle)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(wardrobeSwitcherCaption)
                                .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 8)

            wardrobeSwitcherChevron(
                systemName: "chevron.right",
                visible: isWardrobeGridLayout
                    ? (wardrobeSwitcherShowsPageArrows && wardrobePageIndex < wardrobePageCount - 1)
                    : wardrobeDayIndex < tripWardrobeDays.count - 1
            ) {
                if isWardrobeGridLayout {
                    wardrobeDayIndex = min(
                        max(tripWardrobeDays.count - 1, 0),
                        (wardrobePageIndex + 1) * wardrobePageSize
                    )
                } else {
                    wardrobeDayIndex = min(tripWardrobeDays.count - 1, wardrobeDayIndex + 1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(wardrobeSwitcherTitle). \(wardrobeSwitcherCaption)")
    }

    private func wardrobeSwitcherChevron(
        systemName: String,
        visible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
    }

    private var wardrobeSwitcherTitle: String {
        let trimmedName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        return "This Event"
    }

    private var wardrobeSwitcherCaption: String {
        let totalDays = max(tripWardrobeDays.count, 1)
        if isWardrobeGridLayout {
            let startDay = wardrobePageIndex * wardrobePageSize + 1
            let endDay = min(startDay + wardrobePageSize - 1, totalDays)
            return "Days \(startDay)–\(endDay) of \(totalDays) · Page \(wardrobePageIndex + 1) of \(wardrobePageCount)"
        }
        return "Day \(min(wardrobeDayIndex + 1, totalDays)) of \(totalDays) · \(focusedTripDayLabel)"
    }

    private var focusedTripDayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: focusedTripDay)
    }

    private func shortDayLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter.string(from: day)
    }

    private func dayOOTDIfPresent(for day: Date) -> Event? {
        guard let parent = tempEvent,
              let parentId = parent.id,
              let userId = parent.userId ?? calendarAccountUserId else { return nil }
        return EventTripDayWardrobe.findDayOOTD(
            parentEventId: parentId,
            day: day,
            userId: userId,
            in: viewContext
        )
    }

    private var heroEngagementRow: some View {
        SocialEngagementActionsRow(
            segmentSelection: $heroSegment,
            showsLikeButton: false,
            showsCalendarButton: false,
            showsShareButton: false,
            showsWornSegment: true,
            disabledSegments: heroDisabledSegments,
            isGridLayout: $isWardrobeGridLayout,
            isGridLayoutEnabled: usesPerDayWardrobe
        )
        .onChange(of: hasSelection) { _, hasItemsOrOutfits in
            if !hasItemsOrOutfits, heroSegment == .worn {
                heroSegment = .tshirt
            }
        }
        .onChange(of: isWardrobeGridLayout) { _, isGrid in
            if isGrid {
                wardrobeDayIndex = (wardrobeDayIndex / wardrobePageSize) * wardrobePageSize
                if heroSegment == .worn {
                    heroSegment = .tshirt
                }
            }
        }
        .onChange(of: startDate) { _, _ in
            clampWardrobeDayIndex()
            if !usesPerDayWardrobe {
                isWardrobeGridLayout = false
            }
        }
        .onChange(of: endDate) { _, _ in
            clampWardrobeDayIndex()
            if !usesPerDayWardrobe {
                isWardrobeGridLayout = false
            }
        }
        .onChange(of: isAllDay) { _, _ in
            clampWardrobeDayIndex()
            if !usesPerDayWardrobe {
                isWardrobeGridLayout = false
            }
        }
    }

    /// Worn stays visible in grid at-a-glance but cannot be selected; also disabled until wardrobe has content.
    private var heroDisabledSegments: Set<SocialEngagementToolbarSegment> {
        if isWardrobeGridLayout { return [.worn] }
        if !hasSelection { return [.worn] }
        return []
    }

    private func clampWardrobeDayIndex() {
        let count = tripWardrobeDays.count
        if count == 0 {
            wardrobeDayIndex = 0
        } else if wardrobeDayIndex >= count {
            wardrobeDayIndex = count - 1
        }
    }

    // MARK: - Wardrobe date remapping

    private func handleDateRangeEditDismissIfNeeded() {
        guard dateEditOpenedSheet == .dateAndTime else {
            dateEditOpenedSheet = nil
            return
        }

        guard dateTimeSheetDidCommit else {
            dateEditOpenedSheet = nil
            dateEditBaselineStart = nil
            dateEditBaselineEnd = nil
            pendingDateRemapDecision = nil
            return
        }
        dateTimeSheetDidCommit = false

        dateEditOpenedSheet = nil
        dateEditBaselineStart = nil
        dateEditBaselineEnd = nil

        evaluateWardrobeRemapAfterDateEdit()
    }

    private func calendarDaysMatch(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        let aDays = EventTripDayWardrobe.days(from: aStart, to: aEnd)
        let bDays = EventTripDayWardrobe.days(from: bStart, to: bEnd)
        guard aDays.count == bDays.count else { return false }
        let calendar = Calendar.current
        return zip(aDays, bDays).allSatisfy { calendar.isDate($0, inSameDayAs: $1) }
    }

    private func evaluateWardrobeRemapAfterDateEdit() {
        let calendar = Calendar.current
        let alignedStart = wardrobeAlignedStart
        let alignedEnd = wardrobeAlignedEnd
        let decision = pendingDateRemapDecision
        pendingDateRemapDecision = nil

        // Same calendar days (e.g. all-day ↔ timed only) — no wardrobe remapping.
        if calendarDaysMatch(alignedStart, alignedEnd, startDate, endDate) {
            wardrobeAlignedStart = startDate
            wardrobeAlignedEnd = endDate
            clampWardrobeDayIndex()
            return
        }

        let oldDays = EventTripDayWardrobe.days(from: alignedStart, to: alignedEnd)
        let newDays = EventTripDayWardrobe.days(from: startDate, to: endDate)
        let oldMulti = oldDays.count > 1
        let newMulti = newDays.count > 1
        let startDayChanged = !calendar.isDate(alignedStart, inSameDayAs: startDate)
        let dayCountChanged = oldDays.count != newDays.count

        guard let parent = tempEvent ?? eventToEdit,
              let userId = parent.userId ?? calendarAccountUserId else {
            wardrobeAlignedStart = startDate
            wardrobeAlignedEnd = endDate
            clampWardrobeDayIndex()
            return
        }

        // Ensure tempEvent exists when remapping day OOTDs during create.
        if tempEvent == nil {
            tempEvent = parent
        }

        let hasDayContent = EventTripDayWardrobe.hasAnyDayWardrobeContent(
            forParent: parent,
            userId: userId,
            in: viewContext
        )
        let hasParentContent = EventTripDayWardrobe.hasWardrobeContent(parent)

        if oldMulti && !newMulti {
            EventTripDayWardrobe.foldFirstDayWardrobeOntoParent(
                parent: parent,
                fromDays: oldDays,
                userId: userId,
                in: viewContext
            )
            updateWardrobeAlignment(toStart: startDate, end: endDate)
            return
        }

        if !oldMulti && newMulti {
            if hasParentContent, let firstDay = newDays.first {
                if let dayEvent = EventTripDayWardrobe.promoteParentWardrobeToFirstDay(
                    parent: parent,
                    firstDay: firstDay,
                    userId: userId,
                    in: viewContext
                ), viewContext.insertedObjects.contains(dayEvent) {
                    sessionCreatedDayOOTDObjectIDs.insert(dayEvent.objectID)
                }
            }
            updateWardrobeAlignment(toStart: startDate, end: endDate)
            return
        }

        if oldMulti && newMulti {
            if hasDayContent {
                if decision == .moveOutfits {
                    EventTripDayWardrobe.shiftDayOOTDsByIndex(
                        forParent: parent,
                        fromDays: oldDays,
                        toDays: newDays,
                        userId: userId,
                        in: viewContext
                    )
                }
                // .keepDates (or missing): leave day OOTDs on absolute dates; prune on save.
                updateWardrobeAlignment(toStart: startDate, end: endDate)
                return
            }

            if startDayChanged {
                // No wardrobe content — still re-key any empty day drafts by index.
                EventTripDayWardrobe.shiftDayOOTDsByIndex(
                    forParent: parent,
                    fromDays: oldDays,
                    toDays: newDays,
                    userId: userId,
                    in: viewContext
                )
                updateWardrobeAlignment(toStart: startDate, end: endDate)
                return
            }

            if dayCountChanged, newDays.count < oldDays.count {
                EventTripDayWardrobe.pruneDayOOTDs(
                    forParent: parent,
                    keepingDays: newDays,
                    userId: userId,
                    in: viewContext
                )
            }
            updateWardrobeAlignment(toStart: startDate, end: endDate)
            return
        }

        // Single → single on a different day: wardrobe stays on the parent event.
        updateWardrobeAlignment(toStart: startDate, end: endDate)
    }

    private func updateWardrobeAlignment(toStart start: Date, end: Date) {
        wardrobeAlignedStart = start
        wardrobeAlignedEnd = end
        clampWardrobeDayIndex()
        refreshToken = UUID()
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
        HStack(alignment: .center, spacing: 8) {
            Text("Profile Visibility")
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Menu {
                ForEach(WardrobeVisibility.allCases) { value in
                    Button {
                        eventVisibility = value
                    } label: {
                        Label(value.menuLabel, systemImage: value.iconName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: eventVisibility.iconName)
                    Text(eventVisibility.menuLabel)
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
        .listRowInsets(attributeRowInsets)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile Visibility, \(eventVisibility.menuLabel)")
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


    // MARK: - Chevron field rows

    private var nameRowValue: String {
        let trimmed = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private var occasionRowValue: String {
        let trimmed = eventOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private var themeRowValue: String {
        let trimmed = eventTheme.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private var notesRowValue: String {
        let trimmed = eventNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private var dateSpansMultipleDays: Bool {
        !Calendar.current.isDate(startDate, inSameDayAs: endDate)
    }

    private var dateTimeRowValue: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d"
        if isAllDay {
            let startText = dateFormatter.string(from: startDate)
            if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                return startText
            }
            return "\(startText) – \(dateFormatter.string(from: endDate))"
        }
        return "\(dateTimeLine(for: startDate))\n\(dateTimeLine(for: endDate))"
    }

    private func dateTimeLine(for date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d"
        return "\(dateFormatter.string(from: date)) · \(compactEventTime(date))"
    }

    /// "9AM" when minutes are 0, otherwise "9:30AM".
    private func compactEventTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour24 = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        var text = "\(hour12)"
        if minute != 0 {
            text += String(format: ":%02d", minute)
        }
        text += hour24 < 12 ? "AM" : "PM"
        return text
    }

    private var locationRowValue: String {
        let title = locationDraft.selectedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return locationDraft.eventLocation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var locationRowCaption: String? {
        let subtitle = locationDraft.selectedSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return subtitle.isEmpty ? nil : subtitle
    }

    private var hasLocationForShare: Bool {
        !locationRowValue.isEmpty || !(locationRowCaption ?? "").isEmpty
    }

    private var locationShareText: String {
        if let caption = locationRowCaption, !locationRowValue.isEmpty {
            return "\(locationRowValue)\n\(caption)"
        }
        if !locationRowValue.isEmpty { return locationRowValue }
        return locationRowCaption ?? ""
    }

    private var locationMapsQueryAddress: String? {
        if let caption = locationRowCaption, !caption.isEmpty { return caption }
        let name = locationRowValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private var locationShareLatitude: Double? {
        if let coordinate = locationDraft.selectedPlacemark?.location?.coordinate {
            return coordinate.latitude
        }
        if let event = tempEvent ?? eventToEdit {
            let latitude = event.latitude
            let longitude = event.longitude
            if latitude != 0 || longitude != 0 { return latitude }
        }
        return nil
    }

    private var locationShareLongitude: Double? {
        if let coordinate = locationDraft.selectedPlacemark?.location?.coordinate {
            return coordinate.longitude
        }
        if let event = tempEvent ?? eventToEdit {
            let latitude = event.latitude
            let longitude = event.longitude
            if latitude != 0 || longitude != 0 { return longitude }
        }
        return nil
    }

    private func chevronFieldRow(
        label: String,
        value: String,
        caption: String? = nil,
        allowsMultiline: Bool = false,
        preventsLabelWrapping: Bool = false,
        opens sheet: EventAddFieldSheet
    ) -> some View {
        Button {
            beginFieldSheet(sheet)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(label)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: preventsLabelWrapping, vertical: false)
                Spacer(minLength: 8)
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(value)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(allowsMultiline ? 4 : 1)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: allowsMultiline)
                        if let caption, !caption.isEmpty {
                            Text(caption)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.caption)
                        .padding(.top, 4)
                }
                .modifier(EventAddTrailingValueWidthModifier(constrained: !preventsLabelWrapping))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(attributeRowInsets)
    }

    private func beginFieldSheet(_ sheet: EventAddFieldSheet) {
        if sheet == .dateAndTime {
            dateEditBaselineStart = startDate
            dateEditBaselineEnd = endDate
            dateEditOpenedSheet = sheet
        } else {
            dateEditOpenedSheet = nil
            dateEditBaselineStart = nil
            dateEditBaselineEnd = nil
        }
        activeFieldSheet = sheet
    }

    @ViewBuilder
    private func eventFieldSheet(for sheet: EventAddFieldSheet) -> some View {
        switch sheet {
        case .name:
            EventAddTextFieldSheet(
                title: "Name",
                placeholder: "Event name",
                text: $eventName
            )
        case .occasion:
            EventAddTextFieldSheet(
                title: "Occasion",
                placeholder: "Event occasion",
                text: $eventOccasion
            )
        case .theme:
            EventAddTextFieldSheet(
                title: "Theme",
                placeholder: "Event theme",
                text: $eventTheme
            )
        case .notes:
            EventAddNotesSheet(text: $eventNotes)
        case .dateAndTime:
            EventAddDateTimeSheet(
                startDate: $startDate,
                endDate: $endDate,
                isAllDay: $isAllDay,
                wardrobeAlignedStart: wardrobeAlignedStart,
                wardrobeAlignedEnd: wardrobeAlignedEnd,
                hasDayWardrobeContent: hasDayWardrobeContentForDateSheetWarning,
                onCommit: { decision in
                    pendingDateRemapDecision = decision
                    dateTimeSheetDidCommit = true
                }
            )
        case .location:
            EventAddLocationSheet()
                .environmentObject(locationDraft)
        }
    }

    private var hasDayWardrobeContentForDateSheetWarning: Bool {
        guard let parent = tempEvent ?? eventToEdit,
              let userId = parent.userId ?? calendarAccountUserId else { return false }
        return EventTripDayWardrobe.hasAnyDayWardrobeContent(
            forParent: parent,
            userId: userId,
            in: viewContext
        )
    }

    private func presentationDetents(for sheet: EventAddFieldSheet) -> Set<PresentationDetent> {
        switch sheet {
        case .name, .theme, .occasion:
            return [.height(150)]
        case .dateAndTime:
            return [.height(420)]
        case .notes, .location:
            return [.medium, .large]
        }
    }

    // MARK: - Validation
    /// Title plus a valid date range (timed or all-day) are required to save.
    private var canSaveEvent: Bool {
        let hasTitle = !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasValidDateTime: Bool
        if isAllDay {
            hasValidDateTime = Calendar.current.startOfDay(for: endDate)
                >= Calendar.current.startOfDay(for: startDate)
        } else {
            hasValidDateTime = endDate > startDate
        }
        // Existing location text is enough to save; placemark is only required for a newly entered location.
        let trimmedLocation = locationDraft.eventLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOriginalLocation = originalLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationOK = trimmedLocation.isEmpty
            || locationDraft.selectedPlacemark != nil
            || trimmedLocation == trimmedOriginalLocation
        return hasTitle && hasValidDateTime && locationOK
    }

    private var hasUnsavedChanges: Bool {
        if eventName.trimmingCharacters(in: .whitespacesAndNewlines)
            != originalName.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        if eventTheme.trimmingCharacters(in: .whitespacesAndNewlines)
            != originalTheme.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        if eventOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
            != originalOccasion.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        if locationDraft.eventLocation != originalLocation { return true }
        if eventNotes != originalNotes { return true }
        if isAllDay != originalIsAllDay { return true }
        if eventVisibility != originalVisibility { return true }
        if !datesMatchForEdit(startDate, originalStartDate) { return true }
        if !datesMatchForEdit(endDate, originalEndDate) { return true }
        if usesPerDayWardrobe {
            if currentDayWardrobeFingerprints() != originalDayWardrobeFingerprints { return true }
        } else {
        if selectedItems.map(\.objectID) != originalItems.map(\.objectID) { return true }
        if Set(selectedOutfits.map(\.objectID)) != Set(originalOutfits.map(\.objectID)) { return true }
        }
        return false
    }

    private func datesMatchForEdit(_ lhs: Date, _ rhs: Date) -> Bool {
        let granularity: Calendar.Component = isAllDay ? .day : .minute
        return Calendar.current.compare(lhs, to: rhs, toGranularity: granularity) == .orderedSame
    }

    /// Keeps all-day events at local midnight so date-only pickers cannot drift them to timed values (e.g. 1:00 AM).
    private func normalizeAllDayDatesIfNeeded() {
        guard isAllDay else { return }
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        var normalizedEnd = calendar.startOfDay(for: endDate)
        if normalizedEnd < normalizedStart { normalizedEnd = normalizedStart }
        if calendar.compare(startDate, to: normalizedStart, toGranularity: .minute) != .orderedSame {
            startDate = normalizedStart
        }
        if calendar.compare(endDate, to: normalizedEnd, toGranularity: .minute) != .orderedSame {
            endDate = normalizedEnd
        }
    }

    private func resolvedStartDateForSave() -> Date {
        isAllDay ? Calendar.current.startOfDay(for: startDate) : startDate
    }

    private func resolvedEndDateForSave() -> Date {
        guard isAllDay else { return endDate }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: endDate)
        let start = calendar.startOfDay(for: startDate)
        return max(end, start)
    }

    private func captureOriginals() {
        originalName = eventName
        originalTheme = eventTheme
        originalOccasion = eventOccasion
        originalLocation = locationDraft.eventLocation
        originalNotes = eventNotes
        originalStartDate = startDate
        originalEndDate = endDate
        originalIsAllDay = isAllDay
        originalVisibility = eventVisibility
        originalItems = selectedItems
        originalOutfits = selectedOutfits
        originalDayWardrobeFingerprints = currentDayWardrobeFingerprints()
        wardrobeAlignedStart = startDate
        wardrobeAlignedEnd = endDate
        captureDayOOTDDiscardSnapshots()
        if let event = eventToEdit ?? tempEvent {
            originalLatitude = event.latitude
            originalLongitude = event.longitude
            originalFullAddress = event.fullAddress
        } else {
            originalLatitude = 0
            originalLongitude = 0
            originalFullAddress = nil
        }
    }

    private func attemptCancel() {
        if hasUnsavedChanges {
            showDiscardAlert = true
        } else {
            cancelEditing(discardingChanges: false)
        }
    }

    private func openItemsSelection() {
        if isWardrobeGridLayout {
            isWardrobeGridLayout = false
        }

        if tempEvent == nil {
            createTempEvent()
        } else {
            updateTempEvent()
        }
        guard let parent = tempEvent else { return }
        if parent.objectID.isTemporaryID {
            do {
                try viewContext.obtainPermanentIDs(for: [parent])
            } catch {
                print("Error obtaining permanent ID for event before items selection: \(error)")
                return
            }
        }

        let target: Event
        if usesPerDayWardrobe {
            guard let userId = parent.userId ?? calendarAccountUserId else { return }
            let beforeIDs = Set(viewContext.insertedObjects.compactMap { ($0 as? Event)?.objectID })
            guard let dayEvent = EventTripDayWardrobe.dayOOTD(
                forParent: parent,
                day: focusedTripDay,
                userId: userId,
                in: viewContext,
                createIfNeeded: true
            ) else { return }
            if dayEvent.objectID.isTemporaryID {
                do {
                    try viewContext.obtainPermanentIDs(for: [dayEvent])
                } catch {
                    print("Error obtaining permanent ID for day OOTD before items selection: \(error)")
                    return
                }
            }
            if !beforeIDs.contains(dayEvent.objectID), viewContext.insertedObjects.contains(dayEvent) {
                sessionCreatedDayOOTDObjectIDs.insert(dayEvent.objectID)
            }
            dayEvent.eventVisibility = parent.eventVisibility
            target = dayEvent
        } else {
            target = parent
        }

        navigationPath.append(CalendarRoute.items(target.objectID.uriRepresentation().absoluteString))
    }

    private func cancelEditing(discardingChanges: Bool) {
        if let event = eventToEdit {
            if discardingChanges {
                discardSessionDayOOTDsIfNeeded()
                restoreDayOOTDsFromDiscardSnapshots()
                restoreEventFromOriginals(event)
            }
            dismiss()
            return
        }

        discardSessionDayOOTDsIfNeeded()

        // New event: remove any temp/draft row created during this session.
        if let event = tempEvent {
            if event.objectID.isTemporaryID {
                viewContext.delete(event)
            } else {
                softDelete(event)
                do {
                    try viewContext.save()
                    SyncService.shared.syncEventIfNeeded(event)
                } catch {
                    print("Error soft-deleting unsaved event: \(error)")
                }
            }
        }
        dismiss()
    }

    private func captureDayOOTDDiscardSnapshots() {
        dayOOTDDiscardSnapshots = []
        guard let parent = eventToEdit ?? tempEvent,
              let userId = parent.userId ?? calendarAccountUserId else { return }
        let linked = EventTripDayWardrobe.linkedDayOOTDs(
            forParent: parent,
            userId: userId,
            in: viewContext
        )
        dayOOTDDiscardSnapshots = linked.map { DayOOTDDiscardSnapshot(event: $0) }
    }

    private func restoreDayOOTDsFromDiscardSnapshots() {
        guard !dayOOTDDiscardSnapshots.isEmpty else { return }
        for snapshot in dayOOTDDiscardSnapshots {
            guard let event = try? viewContext.existingObject(with: snapshot.objectID) as? Event else {
                continue
            }
            event.startDate = snapshot.startDate
            event.endDate = snapshot.endDate
            event.date = snapshot.date
            restoreSoftDeleted(event)

            if let existingItems = event.items as? NSOrderedSet {
                event.removeFromItems(existingItems)
            }
            for uri in snapshot.itemURIs {
                if let item = managedItem(forURI: uri) {
                    event.addToItems(item)
                }
            }

            if let existingOutfits = event.outfits as? Set<Outfit> {
                for outfit in existingOutfits {
                    event.removeFromOutfits(outfit)
                }
            }
            for uri in snapshot.outfitURIs {
                if let outfit = managedOutfit(forURI: uri) {
                    event.addToOutfits(outfit)
                }
            }
            setUpdatedAt(event)
        }
    }

    private func managedItem(forURI uriString: String) -> Item? {
        guard let url = URL(string: uriString),
              let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let item = try? viewContext.existingObject(with: objectID) as? Item else {
            return nil
        }
        return item
    }

    private func managedOutfit(forURI uriString: String) -> Outfit? {
        guard let url = URL(string: uriString),
              let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let outfit = try? viewContext.existingObject(with: objectID) as? Outfit else {
            return nil
        }
        return outfit
    }

    private func restoreEventFromOriginals(_ event: Event) {
        event.name = originalName.isEmpty ? nil : originalName
        event.theme = originalTheme.isEmpty ? nil : originalTheme
        event.occasion = originalOccasion.isEmpty ? nil : originalOccasion
        event.location = originalLocation.isEmpty ? nil : originalLocation
        event.notes = originalNotes.isEmpty ? nil : originalNotes
        event.startDate = originalStartDate
        event.endDate = originalEndDate
        event.eventVisibility = originalVisibility
        event.latitude = originalLatitude
        event.longitude = originalLongitude
        event.fullAddress = originalFullAddress

        if let existingItems = event.items as? NSOrderedSet {
            event.removeFromItems(existingItems)
        }
        for item in originalItems {
            event.addToItems(item)
        }

        if let existingOutfits = event.outfits as? Set<Outfit> {
            for outfit in existingOutfits {
                event.removeFromOutfits(outfit)
            }
        }
        for outfit in originalOutfits {
            event.addToOutfits(outfit)
        }

        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
            SyncService.shared.syncEventIfNeeded(event)
        } catch {
            print("Error restoring event after discard: \(error)")
        }
    }

    private var minEndDate: Date {
        if isAllDay {
            // For all-day events, minimum is the start of the start date
            return Calendar.current.startOfDay(for: startDate)
        } else {
            // For timed events, minimum is 1 minute after start
            return startDate.addingTimeInterval(60)
        }
    }
    
    /* MARK: - Duration
    private var durationString: String {
        let seconds = endDate.timeIntervalSince(startDate)
        guard seconds > 0 else { return "Invalid duration" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        
        if days > 0 {
            let remainingHours = hours % 24
            return "\(days) day\(days > 1 ? "s" : "") \(remainingHours) hr"
        } else if hours > 0 {
            let remainingMinutes = minutes % 60
            return "\(hours) hr \(remainingMinutes) min"
        } else {
            return "\(minutes) min"
        }
    }
    */
    // MARK: - Load Event for Editing
    private func loadEventForEditing(_ event: Event) {
        eventName = event.name ?? ""
        eventTheme = event.theme ?? ""
        eventOccasion = event.occasion ?? ""
        locationDraft.reset()
        locationDraft.eventLocation = event.location ?? ""
        eventNotes = event.notes ?? ""
        eventVisibility = event.eventVisibility
        
        if let location = event.location {
            locationDraft.selectedTitle = location
        }
        if let fullAddress = event.fullAddress {
            locationDraft.selectedSubtitle = fullAddress
        }
        
        if let latitude = event.latitude as Double?, latitude != 0,
           let longitude = event.longitude as Double?, longitude != 0 {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                if let placemark = placemarks?.first {
                    DispatchQueue.main.async {
                        locationDraft.selectedPlacemark = placemark
                    }
                }
            }
        }
        
        // Determine if all-day based on times, then pin both ends to local start-of-day.
        if let start = event.startDate, let end = event.endDate {
            let calendar = Calendar.current
            let startComponents = calendar.dateComponents([.hour, .minute, .second], from: start)
            let endComponents = calendar.dateComponents([.hour, .minute, .second], from: end)
            let startsAtMidnight = (startComponents.hour ?? 0) == 0
                && (startComponents.minute ?? 0) == 0
                && (startComponents.second ?? 0) == 0
            let endsAtMidnight = (endComponents.hour ?? 0) == 0
                && (endComponents.minute ?? 0) == 0
                && (endComponents.second ?? 0) == 0
            isAllDay = startsAtMidnight && endsAtMidnight
            startDate = start
            endDate = end
            normalizeAllDayDatesIfNeeded()
        }
    }
    
    // MARK: - Temp Event
    private func createTempEvent() {
        if tempEvent == nil {
            // Use existing event if editing, otherwise create new
            let newEvent = eventToEdit ?? Event(context: viewContext)
            if eventToEdit == nil {
                newEvent.id = UUID()
                newEvent.userId = calendarAccountUserId
                newEvent.eventVisibility = .private
                setCreatedAndUpdatedAt(newEvent)
            }
            // Set initial values, will be updated on save
            newEvent.name = eventName.isEmpty ? nil : eventName
            newEvent.theme = {
                let trimmed = eventTheme.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()
            newEvent.occasion = {
                let trimmed = eventOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()
            newEvent.location = resolvedLocationNameForSave()
            newEvent.startDate = resolvedStartDateForSave()
            newEvent.endDate = resolvedEndDateForSave()
            newEvent.timestamp = eventToEdit?.timestamp ?? Date()
            newEvent.notes = {
                let trimmed = eventNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()
            newEvent.eventVisibility = eventVisibility
            
            applyLocationCoordinatesAndAddress(to: newEvent)
            
            tempEvent = newEvent
        } else {
            // Update existing temp event with current values
            updateTempEvent()
        }
    }
    
    private func updateTempEvent() {
        guard let event = tempEvent else { return }
        event.name = eventName.isEmpty ? nil : eventName
        event.theme = {
            let trimmed = eventTheme.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        event.occasion = {
            let trimmed = eventOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        event.location = resolvedLocationNameForSave()
        event.startDate = resolvedStartDateForSave()
        event.endDate = resolvedEndDateForSave()
        event.notes = {
            let trimmed = eventNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        event.eventVisibility = eventVisibility
        
        applyLocationCoordinatesAndAddress(to: event)
    }

    /// Prefer the search-list title so saved/display names match what the user picked.
    private func resolvedLocationNameForSave() -> String? {
        let title = locationDraft.selectedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        let fallback = locationDraft.eventLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
    }

    private func applyLocationCoordinatesAndAddress(to event: Event) {
        if let placemark = locationDraft.selectedPlacemark {
            event.latitude = placemark.location?.coordinate.latitude ?? 0
            event.longitude = placemark.location?.coordinate.longitude ?? 0
        }

        let subtitle = locationDraft.selectedSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !subtitle.isEmpty {
            event.fullAddress = subtitle
            return
        }
        guard let placemark = locationDraft.selectedPlacemark,
              let postalAddress = placemark.postalAddress else { return }
        let formatter = CNPostalAddressFormatter()
        event.fullAddress = formatter.string(from: postalAddress).replacingOccurrences(of: "\n", with: ", ")
    }
    
    // MARK: - Save

    private func wardrobeFingerprint(for event: Event?) -> String {
        let thumbs = EventTripDayWardrobe.thumbnails(for: event)
        return thumbs.map { $0.id.uriRepresentation().absoluteString }.joined(separator: "|")
    }

    private func currentDayWardrobeFingerprints() -> [TimeInterval: String] {
        guard usesPerDayWardrobe,
              let parent = tempEvent ?? eventToEdit,
              let parentId = parent.id,
              let userId = parent.userId ?? calendarAccountUserId else { return [:] }
        var result: [TimeInterval: String] = [:]
        for day in tripWardrobeDays {
            let key = Calendar.current.startOfDay(for: day).timeIntervalSince1970
            let ootd = EventTripDayWardrobe.findDayOOTD(
                parentEventId: parentId,
                day: day,
                userId: userId,
                in: viewContext
            )
            result[key] = wardrobeFingerprint(for: ootd)
        }
        return result
    }

    private func discardSessionDayOOTDsIfNeeded() {
        for objectID in sessionCreatedDayOOTDObjectIDs {
            if let event = try? viewContext.existingObject(with: objectID) as? Event {
                softDelete(event)
            }
        }
        sessionCreatedDayOOTDObjectIDs.removeAll()
    }

    private func refreshWardrobeEventsFromStore() {
        viewContext.processPendingChanges()
        if let event = tempEvent {
            viewContext.refresh(event, mergeChanges: true)
        }
        guard usesPerDayWardrobe,
              let parent = tempEvent ?? eventToEdit,
              let parentId = parent.id,
              let userId = parent.userId ?? calendarAccountUserId else { return }
        for day in tripWardrobeDays {
            if let dayEvent = EventTripDayWardrobe.findDayOOTD(
                parentEventId: parentId,
                day: day,
                userId: userId,
                in: viewContext
            ) {
                viewContext.refresh(dayEvent, mergeChanges: true)
            }
        }
    }

    private func shouldPromptSaveWardrobeOnEventSave() -> Bool {
        refreshWardrobeEventsFromStore()
        if usesPerDayWardrobe {
            guard let parent = tempEvent,
                  let userId = parent.userId ?? calendarAccountUserId else { return false }
            return hasPerDayOOTDsWithMultipleLooseItems(parent: parent, userId: userId)
        }
        guard let wardrobeEvent = wardrobeSourceEvent ?? tempEvent else { return false }
        return EventTripDayWardrobe.shouldPromptSaveLooseItemsAsOutfit(on: wardrobeEvent)
            || selectedItems.count > 1
    }

    private func attemptSaveEvent() {
        guard canSaveEvent, hasUnsavedChanges else { return }
        normalizeAllDayDatesIfNeeded()
        if tempEvent == nil {
            createTempEvent()
        } else {
            updateTempEvent()
        }
        guard tempEvent != nil else { return }

        if shouldPromptSaveWardrobeOnEventSave() {
            showSaveAsOutfitAlert = true
            return
        }
        commitSaveEvent(saveMultipleAsOutfit: nil)
    }

    private func hasPerDayOOTDsWithMultipleLooseItems(parent: Event, userId: String) -> Bool {
        let days = EventTripDayWardrobe.days(from: startDate, to: endDate)
        return days.contains { day in
            guard let dayEvent = EventTripDayWardrobe.findDayOOTD(
                parentEventId: parent.id ?? UUID(),
                day: day,
                userId: userId,
                in: viewContext
            ) else { return false }
            return EventTripDayWardrobe.shouldPromptSaveLooseItemsAsOutfit(on: dayEvent)
        }
    }

    private func commitSaveEvent(saveMultipleAsOutfit: Bool?) {
        guard canSaveEvent else { return }
        guard hasUnsavedChanges || saveMultipleAsOutfit != nil else { return }

        normalizeAllDayDatesIfNeeded()

        // Ensure temp event exists and is updated
        if tempEvent == nil {
            createTempEvent()
        } else {
            updateTempEvent()
        }

        guard let event = tempEvent else { return }

        event.name = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTheme = eventTheme.trimmingCharacters(in: .whitespacesAndNewlines)
        event.theme = trimmedTheme.isEmpty ? nil : trimmedTheme
        let trimmedOccasion = eventOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        event.occasion = trimmedOccasion.isEmpty ? nil : trimmedOccasion
        let trimmedNotes = eventNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        event.eventVisibility = eventVisibility

        syncEventUserIdFromLinkedEntities(event)
        if (event.userId == nil || (event.userId ?? "").isEmpty), let uid = calendarAccountUserId {
            event.userId = uid
        }

        if event.createdAt == nil {
            setCreatedAndUpdatedAt(event)
        } else {
            setUpdatedAt(event)
        }

        var newlyCreatedOutfits: [Outfit] = []
        var dayEventsToSync: [Event] = []
        if usesPerDayWardrobe, let userId = event.userId ?? calendarAccountUserId {
            let days = EventTripDayWardrobe.days(from: startDate, to: endDate)
            EventTripDayWardrobe.pruneDayOOTDs(
                forParent: event,
                keepingDays: days,
                userId: userId,
                in: viewContext
            )
            for day in days {
                guard let dayEvent = EventTripDayWardrobe.findDayOOTD(
                    parentEventId: event.id ?? UUID(),
                    day: day,
                    userId: userId,
                    in: viewContext
                ) else { continue }
                dayEvent.eventVisibility = event.eventVisibility
                if EventTripDayWardrobe.shouldMaterializeLooseItemsOnSave(
                    on: dayEvent,
                    saveMultipleAsOutfit: saveMultipleAsOutfit
                ),
                   let outfit = EventTripDayWardrobe.materializeLooseItemsIfNeeded(
                    on: dayEvent,
                    userId: userId,
                    in: viewContext
                ) {
                    newlyCreatedOutfits.append(outfit)
                }
                if dayEvent.createdAt == nil {
                    setCreatedAndUpdatedAt(dayEvent)
                } else {
                    setUpdatedAt(dayEvent)
                }
                dayEventsToSync.append(dayEvent)
            }
            // Multi-day wardrobe lives on day OOTDs — clear loose selection on the trip event itself.
            if let existingItems = event.items as? NSOrderedSet {
                event.removeFromItems(existingItems)
            }
            if let existingOutfits = event.outfits as? Set<Outfit> {
                for outfit in existingOutfits {
                    event.removeFromOutfits(outfit)
                }
            }
        } else if let userId = event.userId ?? calendarAccountUserId,
                  EventTripDayWardrobe.shouldMaterializeLooseItemsOnSave(
                    on: event,
                    saveMultipleAsOutfit: saveMultipleAsOutfit
                  ),
                  let outfit = EventTripDayWardrobe.materializeLooseItemsIfNeeded(
                    on: event,
                    userId: userId,
                    in: viewContext
                  ) {
            newlyCreatedOutfits.append(outfit)
        }

        do {
            try viewContext.save()
            for outfit in newlyCreatedOutfits {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            for dayEvent in dayEventsToSync {
                SyncService.shared.syncEventIfNeeded(dayEvent)
            }
            SyncService.shared.syncEventIfNeeded(event)
            sessionCreatedDayOOTDObjectIDs.removeAll()
            dismiss()
        } catch {
            print("Error saving event: \(error)")
        }
    }

    @MainActor
    private func loadEventParticipants() async {
        guard authSession.isAuthenticated else {
            eventParticipants = []
            return
        }
        guard let eventId = (eventToEdit ?? tempEvent)?.id else {
            eventParticipants = []
            return
        }
        do {
            eventParticipants = try await supabaseService.fetchEventParticipants(eventId: eventId)
        } catch {
            print("⚠️ Could not load event participants: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func ensureEventSavedForInvite() async throws -> UUID {
        let trimmedName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(
                domain: "EventAddView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Add an event name before inviting friends."]
            )
        }

        if tempEvent == nil {
            createTempEvent()
        } else {
            updateTempEvent()
        }

        guard let event = tempEvent else {
            throw NSError(
                domain: "EventAddView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not prepare this event."]
            )
        }

        event.name = trimmedName
        syncEventUserIdFromLinkedEntities(event)
        if (event.userId == nil || (event.userId ?? "").isEmpty), let uid = calendarAccountUserId {
            event.userId = uid
        }

        if event.objectID.isTemporaryID {
            try viewContext.obtainPermanentIDs(for: [event])
        }

        if event.createdAt == nil {
            setCreatedAndUpdatedAt(event)
        } else {
            setUpdatedAt(event)
        }

        try viewContext.save()
        try await SyncService.shared.syncEventNow(event)

        guard let eventId = event.id else {
            throw NSError(
                domain: "EventAddView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not sync this event."]
            )
        }
        return eventId
    }
}

// MARK: - Event invites

private enum EventInvitesSegment: String, CaseIterable, Identifiable {
    case participants
    case friends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .participants: return "Participants"
        case .friends: return "Friends"
        }
    }
}

private struct EventParticipantsSheet: View {
    let hostProfile: PublicUserProfile?
    let eventName: String
    @Binding var participants: [EventParticipantRecord]
    let onEnsureEventSaved: () async throws -> UUID

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var selectedSegment: EventInvitesSegment = .friends
    @State private var isLoadingParticipants = false
    @State private var actionError: String?
    @State private var invitingUserId: UUID?

    private static let maxParticipants = 4

    private var rosterParticipants: [EventParticipantRecord] {
        participants.filter { $0.status == "pending" || $0.status == "accepted" || $0.role == "host" }
    }

    /// Already invited / accepted / host — hide from Friends invite list.
    private var inviteExcludedUserIds: Set<UUID> {
        Set(rosterParticipants.map(\.userId))
    }

    private var isEventFull: Bool {
        rosterParticipants.count >= Self.maxParticipants
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SelectionPanelHeader(title: "Invites") {
                    Picker("", selection: $selectedSegment) {
                        ForEach(EventInvitesSegment.allCases) { segment in
                            Text(segment.title).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if let actionError {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }
                Group {
                    switch selectedSegment {
                    case .participants:
                        participantsList
                    case .friends:
                        friendsInviteList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(.systemBackground))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .task {
            let hasTitle = !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasTitle {
                await reloadParticipants()
            }
        }
    }

    @ViewBuilder
    private var participantsList: some View {
        if !authSession.isAuthenticated {
            Text("Sign in to see participants.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoadingParticipants, rosterParticipants.isEmpty, hostProfile == nil {
            ProgressView("Loading participants…")
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if isLoadingParticipants, rosterParticipants.isEmpty {
                    ProgressView("Loading participants…")
                        .listRowBackground(Color(.systemBackground))
                }

                if rosterParticipants.isEmpty, let hostProfile {
                    EventParticipantRow(profile: hostProfile)
                        .listRowBackground(Color(.systemBackground))
                }

                ForEach(rosterParticipants) { participant in
                    EventParticipantRow(
                        profile: participant.publicProfile,
                        statusLabel: participant.statusLabel
                    )
                    .listRowBackground(Color(.systemBackground))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private var friendsInviteList: some View {
        if !authSession.isAuthenticated {
            Text("Sign in to invite friends.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let userId = authSession.userId {
            if isEventFull {
                Text("This event is full (maximum \(Self.maxParticipants) participants).")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FriendsListView(
                    userId: userId,
                    emptyMessage: "You don’t have any mutual friends yet.",
                    exclusionEmptyMessage: "Everyone you’re friends with is already on this event.",
                    excludedUserIds: inviteExcludedUserIds,
                    isPushed: false,
                    allowsOpeningProfile: false
                ) { friend in
                    inviteTrailingControl(for: friend)
                }
            }
        } else {
            Text("Sign in to invite friends.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func inviteTrailingControl(for friend: PublicUserProfile) -> some View {
        let isInvitingThisRow = invitingUserId == friend.userId
        let isDisabled = invitingUserId != nil && invitingUserId != friend.userId

        Button {
            Task { await inviteFriend(friend) }
        } label: {
            if isInvitingThisRow {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(minWidth: 44, minHeight: 28)
            } else {
                Text("Invite")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .disabled(isDisabled || isInvitingThisRow)
        .accessibilityLabel("Invite \(friend.username)")
    }

    private func inviteFriend(_ friend: PublicUserProfile) async {
        guard !inviteExcludedUserIds.contains(friend.userId) else { return }
        guard !isEventFull else {
            await MainActor.run {
                actionError = "This event is full (maximum \(Self.maxParticipants) participants)."
            }
            return
        }

        await MainActor.run {
            invitingUserId = friend.userId
            actionError = nil
        }

        do {
            let eventId = try await onEnsureEventSaved()
            _ = try await supabaseService.inviteToEvent(eventId: eventId, userId: friend.userId)
            await reloadParticipants()
        } catch {
            await MainActor.run {
                actionError = error.localizedDescription
            }
        }

        await MainActor.run {
            invitingUserId = nil
        }
    }

    private func reloadParticipants() async {
        guard authSession.isAuthenticated else { return }

        await MainActor.run {
            isLoadingParticipants = true
            actionError = nil
        }

        do {
            let eventId = try await onEnsureEventSaved()
            let list = try await supabaseService.fetchEventParticipants(eventId: eventId)
            await MainActor.run {
                participants = list
                isLoadingParticipants = false
            }
        } catch {
            let trimmedName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                await MainActor.run {
                    isLoadingParticipants = false
                }
                return
            }
            await MainActor.run {
                isLoadingParticipants = false
                if participants.isEmpty {
                    actionError = error.localizedDescription
                }
            }
        }
    }
}

struct EventParticipantRow: View {
    let profile: PublicUserProfile
    var statusLabel: String? = nil

    private var trimmedDisplayName: String {
        profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var trimmedUsername: String {
        let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? "You" : username
    }

    var body: some View {
        HStack(spacing: 12) {
            PublicUserProfileAvatarView(profile: profile, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(trimmedUsername)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !trimmedDisplayName.isEmpty {
                    Text(trimmedDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let statusLabel {
                Text(statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Location Search View


// MARK: - Event Add field sheets

private struct DayOOTDDiscardSnapshot {
    let objectID: NSManagedObjectID
    let startDate: Date?
    let endDate: Date?
    let date: Date?
    let itemURIs: [String]
    let outfitURIs: [String]

    init(event: Event) {
        objectID = event.objectID
        startDate = event.startDate
        endDate = event.endDate
        date = event.date
        let items: [Item] = {
            guard let ordered = event.items as? NSOrderedSet else { return [] }
            return ordered.array as? [Item] ?? []
        }()
        itemURIs = items.map { $0.objectID.uriRepresentation().absoluteString }
        let outfits: [Outfit] = {
            guard let set = event.outfits as? Set<Outfit> else { return [] }
            return Array(set)
        }()
        outfitURIs = outfits.map { $0.objectID.uriRepresentation().absoluteString }
    }
}

private enum EventDateRemapDecision {
    case keepDates
    case moveOutfits
}

private enum EventWardrobeRemapCopy {
    static let message =
        "This event already has outfits on specific days. Move them to the new dates, or keep them on their current dates?"
}

private enum EventAddFieldSheet: String, Identifiable {
    case name, occasion, theme, notes, dateAndTime, location
    var id: String { rawValue }
}

private struct EventAddTrailingValueWidthModifier: ViewModifier {
    let constrained: Bool

    func body(content: Content) -> some View {
        if constrained {
            content.containerRelativeFrame(.horizontal, alignment: .trailing) { length, _ in
                length * 0.6
            }
        } else {
            content
        }
    }
}

private struct EventAddTextFieldSheet: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(title: String, placeholder: String, text: Binding<String>) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        _draft = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 12) {
            SelectionPanelHeader(title: title)
            HStack {
                AutofocusTextField(
                    text: $draft,
                    placeholder: placeholder,
                    autocapitalizationType: .words
                )
                Button("Save") {
                    text = draft
                    dismiss()
                }
            }
            .padding(.horizontal)
            Spacer()
        }
    }
}

private struct EventAddNotesSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 16) {
            SelectionPanelHeader(title: "Notes")
            TextEditor(text: $draft)
                .frame(minHeight: 200)
                .padding(4)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .focused($isFocused)
                .padding(.horizontal)
            Button("Save") {
                text = draft
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .onAppear {
            draft = text
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}

private struct EventAddDateTimeSheet: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var isAllDay: Bool
    var wardrobeAlignedStart: Date
    var wardrobeAlignedEnd: Date
    var hasDayWardrobeContent: Bool
    var onCommit: (EventDateRemapDecision?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftStartDate: Date = Date()
    @State private var draftEndDate: Date = Date()
    @State private var draftIsAllDay = false
    @State private var remapSelection: EventDateRemapDecision?

    /// Multi-day range with day outfits whose calendar day set changed (start and/or end).
    private var requiresRemapChoice: Bool {
        let calendar = Calendar.current
        let alignedDays = EventTripDayWardrobe.days(from: wardrobeAlignedStart, to: wardrobeAlignedEnd)
        let draftDays = EventTripDayWardrobe.days(from: draftStartDate, to: draftEndDate)
        let sameCalendarDays = alignedDays.count == draftDays.count
            && zip(alignedDays, draftDays).allSatisfy { calendar.isDate($0, inSameDayAs: $1) }
        guard !sameCalendarDays else { return false }

        let oldMulti = alignedDays.count > 1
        let newMulti = draftDays.count > 1
        return oldMulti && newMulti && hasDayWardrobeContent
    }

    private var canSaveDateTime: Bool {
        !requiresRemapChoice || remapSelection != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: "Date & Time") {
                EmptyView()
            } trailing: {
                Button("Save") {
                    commitAndDismiss()
                }
                .disabled(!canSaveDateTime)
            }
            VStack(spacing: 12) {
                Toggle("All-day", isOn: $draftIsAllDay)
                    .padding(.top, 4)
                    .onChange(of: draftIsAllDay) { _, newValue in
                        let calendar = Calendar.current
                        if newValue {
                            draftStartDate = calendar.startOfDay(for: draftStartDate)
                            draftEndDate = calendar.startOfDay(for: draftEndDate)
                            if draftEndDate < draftStartDate { draftEndDate = draftStartDate }
                        } else {
                            draftStartDate = calendar.date(
                                bySettingHour: 9, minute: 0, second: 0, of: draftStartDate
                            ) ?? draftStartDate
                            draftEndDate = calendar.date(
                                bySettingHour: 10, minute: 0, second: 0, of: draftEndDate
                            ) ?? draftEndDate
                            if draftEndDate <= draftStartDate {
                                draftEndDate = draftStartDate.addingTimeInterval(3600)
                            }
                        }
                        clearRemapSelectionIfNeeded()
                    }

                HStack {
                    plainDatePicker(
                        label: "Start Date",
                        selection: $draftStartDate,
                        components: [.date],
                        displayText: compactDateText(draftStartDate)
                    )

                    Spacer(minLength: 8)

                    plainDatePicker(
                        label: "Start Time",
                        selection: $draftStartDate,
                        components: [.hourAndMinute],
                        displayText: compactTimeText(draftStartDate),
                        alignment: .trailing
                    )
                    .opacity(draftIsAllDay ? 0 : 1)
                    .allowsHitTesting(!draftIsAllDay)
                    .accessibilityHidden(draftIsAllDay)
                }
                .onChange(of: draftStartDate) { _, _ in
                    let calendar = Calendar.current
                    if draftIsAllDay {
                        let normalized = calendar.startOfDay(for: draftStartDate)
                        if normalized != draftStartDate {
                            draftStartDate = normalized
                            return
                        }
                    }
                    if calendar.startOfDay(for: draftEndDate) < calendar.startOfDay(for: draftStartDate) {
                        draftEndDate = draftIsAllDay
                            ? calendar.startOfDay(for: draftStartDate)
                            : merge(day: draftStartDate, time: draftEndDate)
                    } else if !draftIsAllDay, draftEndDate <= draftStartDate {
                        draftEndDate = draftStartDate.addingTimeInterval(3600)
                    }
                    clearRemapSelectionIfNeeded()
                }

                HStack {
                    plainDatePicker(
                        label: "End Date",
                        selection: $draftEndDate,
                        components: [.date],
                        range: Calendar.current.startOfDay(for: draftStartDate)...,
                        displayText: compactDateText(draftEndDate)
                    )

                    Spacer(minLength: 8)

                    plainDatePicker(
                        label: "End Time",
                        selection: $draftEndDate,
                        components: [.hourAndMinute],
                        range: draftStartDate.addingTimeInterval(60)...,
                        displayText: compactTimeText(draftEndDate),
                        alignment: .trailing
                    )
                    .opacity(draftIsAllDay ? 0 : 1)
                    .allowsHitTesting(!draftIsAllDay)
                    .accessibilityHidden(draftIsAllDay)
                }
                .onChange(of: draftEndDate) { _, _ in
                    if draftIsAllDay {
                        let calendar = Calendar.current
                        var normalized = calendar.startOfDay(for: draftEndDate)
                        if normalized < calendar.startOfDay(for: draftStartDate) {
                            normalized = calendar.startOfDay(for: draftStartDate)
                        }
                        if normalized != draftEndDate {
                            draftEndDate = normalized
                        }
                    } else if draftEndDate <= draftStartDate {
                        draftEndDate = draftStartDate.addingTimeInterval(3600)
                    }
                    clearRemapSelectionIfNeeded()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(EventWardrobeRemapCopy.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    HStack(spacing: 10) {
                        remapChoiceButton(title: "Keep Dates", choice: .keepDates)
                        remapChoiceButton(title: "Move Outfits", choice: .moveOutfits)
                    }
                }
                .opacity(requiresRemapChoice ? 1 : 0)
                .accessibilityHidden(!requiresRemapChoice)
                .allowsHitTesting(requiresRemapChoice)
            }
            .padding(.horizontal)
            Spacer(minLength: 0)
        }
        .onAppear {
            UIDatePicker.appearance().minuteInterval = 5
            draftStartDate = startDate
            draftEndDate = endDate
            draftIsAllDay = isAllDay
            if draftIsAllDay {
                let calendar = Calendar.current
                draftStartDate = calendar.startOfDay(for: draftStartDate)
                draftEndDate = calendar.startOfDay(for: draftEndDate)
            }
            remapSelection = nil
        }
        .presentationDetents([.height(420)])
    }

    private func remapChoiceButton(title: String, choice: EventDateRemapDecision) -> some View {
        let isSelected = remapSelection == choice
        return Button {
            remapSelection = choice
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.secondarySystemFill))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func clearRemapSelectionIfNeeded() {
        remapSelection = nil
    }

    private func commitAndDismiss() {
        guard canSaveDateTime else { return }
        startDate = draftStartDate
        endDate = draftEndDate
        isAllDay = draftIsAllDay
        let decision: EventDateRemapDecision? = requiresRemapChoice ? remapSelection : nil
        onCommit(decision)
        dismiss()
    }

    private func plainDatePicker(
        label: String,
        selection: Binding<Date>,
        components: DatePickerComponents,
        range: PartialRangeFrom<Date>? = nil,
        displayText: String,
        alignment: Alignment = .leading
    ) -> some View {
        ZStack(alignment: alignment) {
            Text(displayText)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Group {
                if let range {
                    DatePicker(
                        label,
                        selection: selection,
                        in: range,
                        displayedComponents: components
                    )
                } else {
                    DatePicker(
                        label,
                        selection: selection,
                        displayedComponents: components
                    )
                }
            }
            .labelsHidden()
            .datePickerStyle(.compact)
            .opacity(0.02)
            .scaleEffect(
                x: 1.6,
                y: 1.2,
                anchor: alignment == .trailing ? .trailing : .leading
            )
        }
        .frame(minHeight: 28, alignment: alignment)
    }

    private func compactDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private func compactTimeText(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour24 = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        var text = "\(hour12)"
        if minute != 0 {
            text += String(format: ":%02d", minute)
        }
        text += hour24 < 12 ? "AM" : "PM"
        return text
    }

    private func merge(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        var dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        dayParts.hour = timeParts.hour
        dayParts.minute = timeParts.minute
        return calendar.date(from: dayParts) ?? day
    }
}

private struct EventAddLocationSheet: View {
    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: "Location")
            LocationSearchView()
                .padding(.top, 12)
        }
    }
}

struct LocationSearchView: View {
    @EnvironmentObject private var locationDraft: EventLocationDraft
    @StateObject private var searchManager = LocationSearchManager()
    @Environment(\.dismiss) private var dismiss
    
    @State private var query = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                AutofocusTextField(
                    text: $query,
                    placeholder: "Search location",
                    borderStyle: .none,
                    autocapitalizationType: .words,
                    autocorrectionType: .no
                )
                .onChange(of: query) { _, newValue in
                    searchManager.updateQuery(newValue)
                }

                if !query.isEmpty {
                    Button {
                        query = ""
                        searchManager.updateQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear location search")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(searchManager.suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.gray)
                                .padding(.top, 2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .foregroundColor(.primary)
                                
                                Text(suggestion.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .onTapGesture {
                            selectSuggestion(suggestion)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .animation(.easeInOut, value: searchManager.suggestions.count)
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if query.isEmpty {
                let existing = locationDraft.selectedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? locationDraft.eventLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                if !existing.isEmpty {
                    query = existing
                    searchManager.updateQuery(existing)
                }
            }
        }
    }

    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: suggestion)
        MKLocalSearch(request: request).start { response, _ in
            guard let placemark = response?.mapItems.first?.placemark else { return }
            DispatchQueue.main.async {
                locationDraft.selectedPlacemark = placemark
                // Persist the completer title/subtitle so the event row matches the search list.
                locationDraft.selectedTitle = suggestion.title
                locationDraft.selectedSubtitle = suggestion.subtitle
                locationDraft.eventLocation = suggestion.title
                dismiss()
            }
        }
    }
}




// MARK: - Location Search Manager
class LocationSearchManager: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }
    
    func updateQuery(_ query: String) {
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.suggestions = completer.results
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Completer error: \(error)")
        DispatchQueue.main.async {
            self.suggestions = []
        }
    }
}


