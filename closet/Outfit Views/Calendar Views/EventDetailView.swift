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
    @ObservedObject var tabBarHideState: TabBarHideState

    /// Bumped when returning from edit so notes/other fields re-render from Core Data.
    @State private var notesRefreshToken = UUID()
    @State private var isWhoExpanded = true
    @State private var isWhatExpanded = true
    @State private var isWhenExpanded = true
    @State private var isWhereExpanded = true
    @State private var isWardrobeExpanded = true
    @State private var heroSegment: SocialEngagementToolbarSegment = .tshirt
    @State private var wardrobeDayIndex = 0
    @State private var isWardrobeGridLayout = false
    @State private var eventParticipants: [EventParticipantRecord] = []
    @State private var showCopiedAddressToast = false

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var supabaseService: SupabaseService

    @FetchRequest(
        entity: UserProfile.entity(),
        sortDescriptors: []
    ) private var allUserProfiles: FetchedResults<UserProfile>

    private var isAllDay: Bool {
        guard let start = event.startDate, let end = event.endDate else { return false }
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        return (startComponents.hour == 0 && startComponents.minute == 0) &&
               (endComponents.hour == 0 && endComponents.minute == 0)
    }

    private var usesPerDayWardrobe: Bool {
        guard let start = event.startDate,
              let end = event.endDate else { return false }
        return !Calendar.current.isDate(start, inSameDayAs: end)
    }

    private var tripWardrobeDays: [Date] {
        guard let start = event.startDate, let end = event.endDate else { return [] }
        return EventTripDayWardrobe.days(from: start, to: end)
    }

    private var focusedTripDay: Date {
        let days = tripWardrobeDays
        guard !days.isEmpty else {
            return Calendar.current.startOfDay(for: event.startDate ?? Date())
        }
        let idx = min(max(wardrobeDayIndex, 0), days.count - 1)
        return days[idx]
    }

    private var wardrobeSourceEvent: Event? {
        if usesPerDayWardrobe {
            guard let parentId = event.id,
                  let userId = event.userId else { return nil }
            return EventTripDayWardrobe.findDayOOTD(
                parentEventId: parentId,
                day: focusedTripDay,
                userId: userId,
                in: viewContext
            )
        }
        return event
    }

    private var selectedItems: [Item] {
        guard let source = wardrobeSourceEvent,
              let itemsOrderedSet = source.items as? NSOrderedSet else { return [] }
        return itemsOrderedSet.array as? [Item] ?? []
    }

    private var selectedOutfits: [Outfit] {
        guard let source = wardrobeSourceEvent,
              let outfitsSet = source.outfits as? Set<Outfit> else { return [] }
        return outfitsSet.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var hasSelection: Bool {
        if usesPerDayWardrobe {
            // Keep WARDROBE visible for multi-day trips even before day outfits exist.
            return true
        }
        return !selectedItems.isEmpty || !selectedOutfits.isEmpty
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
        copyableLocationText != nil
    }

    private var locationNameText: String {
        event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var addressText: String {
        event.fullAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var locationRowPrimary: String {
        if !locationNameText.isEmpty { return locationNameText }
        return addressText
    }

    private var locationRowCaption: String? {
        guard !locationNameText.isEmpty, !addressText.isEmpty else { return nil }
        return addressText
    }

    private var displayedNotes: String? {
        let _ = notesRefreshToken
        let trimmed = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var displayedTheme: String? {
        let _ = notesRefreshToken
        let trimmed = event.theme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var displayedOccasion: String? {
        let _ = notesRefreshToken
        let trimmed = event.occasion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    private var eventNameText: String {
        let trimmed = event.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed
    }

    // MARK: - Date & Time section

    /// Compact time like "9AM" / "9:30AM" — omits :00 minutes.
    private func compactTime(_ date: Date, includePeriod: Bool = true) -> String {
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

    private func dateTimeLine(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return "\(formatter.string(from: date)) · \(compactTime(date))"
    }

    private var dateTimeCombinedLine: String? {
        guard let startDate = event.startDate else { return nil }
        let endDate = event.endDate ?? startDate
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        if isAllDay {
            let startText = formatter.string(from: startDate)
            if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                return startText
            }
            return "\(startText) – \(formatter.string(from: endDate))"
        }
        return "\(dateTimeLine(for: startDate))\n\(dateTimeLine(for: endDate))"
    }

    var body: some View {
        List {
            if hasSelection {
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
            }

            if appCapabilities.enablesCloudSync {
                Section {
                    if isWhoExpanded {
                        privacyRow
                        whoParticipantRows
                    }
                } header: {
                    sectionHeader("WHO", isExpanded: $isWhoExpanded)
                }
                .listSectionSpacing(4)
            }

            Section {
                if isWhatExpanded {
                    detailFieldRow(label: "Name", value: eventNameText)
                    if let occasion = displayedOccasion {
                        detailFieldRow(label: "Occasion", value: occasion)
                    }
                    if let theme = displayedTheme {
                        detailFieldRow(label: "Theme", value: theme)
                    }
                    if let notes = displayedNotes {
                        detailFieldRow(label: "Notes", value: notes, allowsMultiline: true)
                    }
                }
            } header: {
                sectionHeader("WHAT", isExpanded: $isWhatExpanded)
            }
            .listSectionSpacing(4)

            if event.startDate != nil || event.endDate != nil {
                Section {
                    if isWhenExpanded {
                        if let value = dateTimeCombinedLine {
                            detailFieldRow(
                                label: "Date & Time",
                                value: value,
                                caption: isAllDay ? "All-day" : nil,
                                allowsMultiline: !isAllDay && value.contains("\n"),
                                preventsLabelWrapping: true
                            )
                        }
                    }
                } header: {
                    sectionHeader("WHEN", isExpanded: $isWhenExpanded)
                }
                .listSectionSpacing(4)
            }

            if hasEventLocation {
                Section {
                    if isWhereExpanded {
                        detailFieldRow(
                            label: "Location",
                            value: locationRowPrimary,
                            caption: locationRowCaption
                        )
                        EventLocationShareActionsRow(
                            shareText: copyableLocationText ?? locationRowPrimary,
                            mapsQueryAddress: mapsQueryAddress,
                            latitude: event.latitude,
                            longitude: event.longitude,
                            rowInsets: attributeRowInsets,
                            onCopiedAddress: presentCopiedAddressToast
                        )
                    }
                    whereSectionBottomPad
                } header: {
                    sectionHeader("WHERE", isExpanded: $isWhereExpanded)
                }
                .listSectionSpacing(4)
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .id(notesRefreshToken)
        .background(Color(.systemBackground))
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(tabBarHideState.shouldHideTabBar ? .hidden : .automatic, for: .tabBar)
        .onAppear { tabBarHideState.shouldHideTabBar = true }
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
            Task { await loadEventParticipants() }
        }
        .task(id: event.id) {
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

    // MARK: - Rows

    private var itemsHeroRow: some View {
        Color(.systemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay { heroOverlayContent }
            .clipped()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(usesPerDayWardrobe ? "Trip day wardrobe" : "Event items and outfits")
    }

    @ViewBuilder
    private var heroOverlayContent: some View {
        if usesPerDayWardrobe && isWardrobeGridLayout {
            tripDayGridOverlay
        } else if !usesPerDayWardrobe && isWardrobeGridLayout {
            selectionGridOverlay
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
            if hasWardrobeContent {
                EventSelectedItemsDisplayArea(
                    thumbnails: selectedOutfits.map { .outfit($0) }
                        + selectedItems.map { .item($0) },
                    fillsEdgeToEdge: true
                )
            } else {
                Text(usesPerDayWardrobe ? "No outfit for this day" : "No items or outfits")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var hasWardrobeContent: Bool {
        !selectedItems.isEmpty || !selectedOutfits.isEmpty
    }

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
                        Color(.systemBackground)
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
                    Color(.systemBackground)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isActive)
    }

    private var selectionGridOverlay: some View {
        let thumbs = selectedOutfits.map { EventSelectedThumbnail.outfit($0) }
            + selectedItems.map { EventSelectedThumbnail.item($0) }
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
            Color(.systemBackground)
            if let thumb {
                EventSelectedItemsDisplayArea(thumbnails: [thumb], fillsEdgeToEdge: true)
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
        let trimmedName = eventNameText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let parentId = event.id, let userId = event.userId else { return nil }
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
            isGridLayout: $isWardrobeGridLayout
        )
        .onChange(of: isWardrobeGridLayout) { _, isGrid in
            if isGrid {
                wardrobeDayIndex = (wardrobeDayIndex / wardrobePageSize) * wardrobePageSize
                if heroSegment == .worn {
                    heroSegment = .tshirt
                }
            }
        }
    }

    /// Worn stays visible in grid at-a-glance but cannot be selected.
    private var heroDisabledSegments: Set<SocialEngagementToolbarSegment> {
        isWardrobeGridLayout ? [.worn] : []
    }

    private var firstWornHeroImage: UIImage? {
        for outfit in selectedOutfits {
            if let data = outfit.wornImage, let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    private var currentUserProfile: UserProfile? {
        guard let userId = authSession.userId?.uuidString else { return nil }
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

    /// Host profile for WHO: prefer current user when they own the event, else first host record.
    private var whoHostProfile: PublicUserProfile? {
        if let current = currentUserAvatarProfile,
           event.userId == authSession.userId?.uuidString {
            return current
        }
        if let host = eventParticipants.first(where: { $0.role == "host" }) {
            return host.publicProfile
        }
        return currentUserAvatarProfile
    }

    private var whoHostStatusLabel: String {
        if event.userId == authSession.userId?.uuidString {
            return "You"
        }
        return "Host"
    }

    @ViewBuilder
    private var whoParticipantRows: some View {
        if let host = whoHostProfile {
            EventParticipantRow(
                profile: host,
                statusLabel: whoHostStatusLabel
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

    private var privacyRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Profile Visibility")
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: event.eventVisibility.iconName)
                    .foregroundColor(.gray)
                Text(event.eventVisibility.menuLabel)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .listRowInsets(attributeRowInsets)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile Visibility, \(event.eventVisibility.menuLabel)")
    }

    @MainActor
    private func loadEventParticipants() async {
        guard appCapabilities.enablesCloudSync, authSession.isAuthenticated else {
            eventParticipants = []
            return
        }
        guard let eventId = event.id else {
            eventParticipants = []
            return
        }
        do {
            eventParticipants = try await supabaseService.fetchEventParticipants(eventId: eventId)
        } catch {
            print("⚠️ Could not load event participants: \(error.localizedDescription)")
        }
    }

    private func detailFieldRow(
        label: String,
        value: String,
        caption: String? = nil,
        allowsMultiline: Bool = false,
        preventsLabelWrapping: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: preventsLabelWrapping, vertical: false)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(allowsMultiline ? nil : 1)
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

    // MARK: - Map query

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
