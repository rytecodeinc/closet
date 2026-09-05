//
//  CalendarView.swift
//  closet
//
//  Created by Dan Warner on 9/20/25.
//


import SwiftUI
import CoreData
import UIKit

private enum CalendarGridDisplayMode: String, CaseIterable {
    /// Event name bars + OOTD squares + event items/outfits squares.
    case eventsAndOOTD
    /// OOTD and event items/outfits squares only — no event name bars.
    case wardrobeAndOOTD
    /// Event name bars + event items/outfits squares — no OOTD squares.
    case wardrobeWithEventNames
    /// OOTD squares only — no event name bars or event wardrobe.
    case ootdOnly

    var menuTitle: String {
        switch self {
        case .eventsAndOOTD: return "Event Labels, OOTDs & Items/Outfits"
        case .wardrobeAndOOTD: return "OOTDs & Items/Outfits"
        case .wardrobeWithEventNames: return "Event Labels & Items/Outfits"
        case .ootdOnly: return "OOTDs Only"
        }
    }

    var showsEventNames: Bool {
        switch self {
        case .eventsAndOOTD, .wardrobeWithEventNames: return true
        case .wardrobeAndOOTD, .ootdOnly: return false
        }
    }

    var showsOOTDWardrobe: Bool {
        switch self {
        case .eventsAndOOTD, .wardrobeAndOOTD, .ootdOnly: return true
        case .wardrobeWithEventNames: return false
        }
    }

    var showsEventWardrobe: Bool {
        switch self {
        case .eventsAndOOTD, .wardrobeWithEventNames, .wardrobeAndOOTD: return true
        case .ootdOnly: return false
        }
    }
}

struct CalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession
    @StateObject private var tabBarHideState = TabBarHideState()
    @State private var events: [Event] = []

    @State private var selectedDate: Date? = nil
    @State private var showingEventDrawer = false
    @State private var showingDatePicker = false
    @State private var pickerSelectedDate: Date = Date()
    /// Set while dismissing the day drawer; applied as a calendar-stack push in sheet `onDismiss`.
    @State private var pendingEventDetailURI: String?
    @State private var pendingCreateEventDate: Date?
    @State private var navigationPath = NavigationPath()
    @StateObject private var locationDraft = EventLocationDraft()
    @StateObject private var itemsSelectionDraft = EventItemsSelectionDraft()
    
    @State private var currentMonth: Date = Date()
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @AppStorage("calendarGridDisplayMode") private var calendarGridDisplayModeRaw = CalendarGridDisplayMode.eventsAndOOTD.rawValue
        
    private let calendar = Calendar.current

    private var calendarGridDisplayMode: CalendarGridDisplayMode {
        CalendarGridDisplayMode(rawValue: calendarGridDisplayModeRaw) ?? .eventsAndOOTD
    }

    private var showsEventNamesOnGrid: Bool {
        calendarGridDisplayMode.showsEventNames
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geo in
            ZStack(alignment: .top) {
                
                VStack(spacing: 0) {
                   // Divider()
                    daysOfWeekHeader
                    
                    // Calendar grid with drag
                    calendarGrid(for: currentMonth, geo: geo)
                        .offset(y: dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation.height
                                    isDragging = true
                                }
                                .onEnded { value in
                                    let threshold = geo.size.height / 6
                                    if value.translation.height < -threshold {
                                        changeMonth(by: 1)
                                    } else if value.translation.height > threshold {
                                        changeMonth(by: -1)
                                    }
                                    withAnimation(.spring()) {
                                        dragOffset = 0
                                    }
                                    isDragging = false
                                }
                        )
                }
              //  .padding(.top, 8)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(tabBarHideState.shouldHideTabBar ? .hidden : .automatic, for: .tabBar)
                .onChange(of: navigationPath.count) { _, count in
                    tabBarHideState.shouldHideTabBar = count > 0
                }
                .toolbar {
                    // Month/Year selector button
                    ToolbarItem(placement: .principal) {
                        Button(action: {
                            pickerSelectedDate = currentMonth
                            showingDatePicker = true
                        }) {
                            HStack(spacing: 4) {
                                Text(monthYearString(for: currentMonth))
                                    .font(.headline)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            Menu {
                                ForEach(CalendarGridDisplayMode.allCases, id: \.self) { mode in
                                    Button {
                                        calendarGridDisplayModeRaw = mode.rawValue
                                    } label: {
                                        if calendarGridDisplayMode == mode {
                                            Label(mode.menuTitle, systemImage: "checkmark")
                                        } else {
                                            Text(mode.menuTitle)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "eye")
                                    .font(.caption)
                            }
                            .accessibilityLabel("Calendar display")

                            Menu {
                                Button {
                                    navigationPath.append(
                                        CalendarRoute.createOotd(
                                            id: UUID(),
                                            initialDate: selectedDate ?? Date()
                                        )
                                    )
                                } label: {
                                    Label("Outfit of the Day", systemImage: "hanger")
                                }
                                Button {
                                    locationDraft.reset()
                                    navigationPath.append(
                                        CalendarRoute.createEvent(
                                            id: UUID(),
                                            initialDate: selectedDate ?? Date()
                                        )
                                    )
                                } label: {
                                    Label("Event", systemImage: "calendar")
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add")
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 12) {
                            Button(action: { changeMonth(by: -1) }) {
                                Image(systemName: "chevron.up")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            Button(action: { changeMonth(by: 1) }) {
                                Image(systemName: "chevron.down")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            Button(action: {
                                let today = Date()
                                withAnimation(.spring()) {
                                    currentMonth = startOfMonth(for: today)
                                    selectedDate = today
                                }
                            }) {
                                Image(systemName: "calendar.circle")
                            }
                            .accessibilityLabel("Jump to today")
                        }
                    }
                }
                
            }
        }
        .task(id: authSession.userId) {
            fetchEvents()
        }
        .sheet(isPresented: $showingEventDrawer, onDismiss: {
            fetchEvents()
            // Dismiss-then-push: only after the drawer sheet is fully gone.
            if let pending = pendingEventDetailURI {
                pendingEventDetailURI = nil
                DispatchQueue.main.async {
                    navigationPath.append(CalendarRoute.eventDetail(pending))
                }
                return
            }
            if let createDate = pendingCreateEventDate {
                pendingCreateEventDate = nil
                DispatchQueue.main.async {
                    locationDraft.reset()
                    navigationPath.append(
                        CalendarRoute.createEvent(id: UUID(), initialDate: createDate)
                    )
                }
            }
        }) {
            Group {
                if let selectedDate = selectedDate {
                    EventDrawerView(
                        selectedDate: selectedDate,
                        ownerUserId: authSession.userId?.uuidString,
                        onDismiss: {
                            showingEventDrawer = false
                        },
                        onNavigateDate: { newDate in
                            self.selectedDate = newDate
                            self.currentMonth = startOfMonth(for: newDate)
                        },
                        onSelectEvent: { event in
                            pendingEventDetailURI = event.objectID.uriRepresentation().absoluteString
                            showingEventDrawer = false
                        },
                        onCreateEvent: {
                            pendingCreateEventDate = selectedDate
                            showingEventDrawer = false
                        }
                    )
                } else {
                    EmptyView()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(for: CalendarRoute.self) { route in
            calendarDestination(for: route)
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                VStack {
                    MonthYearPicker(selection: $pickerSelectedDate)
                }
                .navigationTitle("Select Month")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            withAnimation(.spring()) {
                                currentMonth = startOfMonth(for: pickerSelectedDate)
                            }
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.fraction(0.75), .height(300)])
        }
        }
        .environmentObject(locationDraft)
        .environmentObject(itemsSelectionDraft)
    }
    
    @ViewBuilder
    private func calendarDestination(for route: CalendarRoute) -> some View {
        switch route {
        case .eventDetail(let uriString):
            if let event = managedEvent(forURI: uriString) {
                if event.isOutfitOfTheDay {
                    OotdDetailView(
                        event: event,
                        navigationPath: $navigationPath,
                        tabBarHideState: tabBarHideState
                    )
                    .environment(\.managedObjectContext, viewContext)
                    .id(event.objectID)
                    .onDisappear { fetchEvents() }
                } else {
                    EventDetailView(
                        event: event,
                        navigationPath: $navigationPath,
                        tabBarHideState: tabBarHideState
                    )
                    .environment(\.managedObjectContext, viewContext)
                    .id(event.objectID)
                    .onDisappear { fetchEvents() }
                }
            } else {
                Text("Event unavailable")
            }
        case .createEvent(_, let initialDate):
            EventAddView(
                eventToEdit: nil,
                initialDate: initialDate,
                navigationPath: $navigationPath
            )
            .environment(\.managedObjectContext, viewContext)
            .environmentObject(locationDraft)
            .onDisappear { fetchEvents() }
        case .createOotd(_, let initialDate):
            OotdAddView(
                eventToEdit: nil,
                initialDate: initialDate,
                navigationPath: $navigationPath
            )
            .environment(\.managedObjectContext, viewContext)
            .onDisappear { fetchEvents() }
        case .editEvent(let uriString):
            if let event = managedEvent(forURI: uriString) {
                if event.isOutfitOfTheDay {
                    OotdAddView(
                        eventToEdit: event,
                        navigationPath: $navigationPath
                    )
                    .environment(\.managedObjectContext, viewContext)
                    .id(event.objectID)
                    .onDisappear { fetchEvents() }
                } else {
                    EventAddView(
                        eventToEdit: event,
                        navigationPath: $navigationPath
                    )
                    .environment(\.managedObjectContext, viewContext)
                    .environmentObject(locationDraft)
                    .id(event.objectID)
                    .onDisappear { fetchEvents() }
                }
            } else {
                Text("Event unavailable")
            }
        case .location:
            LocationSearchView()
                .environmentObject(locationDraft)
        case .items(let uriString):
            if let event = managedEvent(forURI: uriString) {
                EventIndividualItemSelection(event: event, navigationPath: $navigationPath)
                    .environment(\.managedObjectContext, viewContext)
                    .id(event.objectID)
            } else {
                Text("Event unavailable")
            }
        case .itemsFilter:
            ItemFilterView(
                filterModel: itemsSelectionDraft.itemFilterModel,
                tabBarHideState: itemsSelectionDraft.tabBarHideState,
                wardrobeType: "closet",
                selectedWardrobe: itemsSelectionDraft.selectedWardrobe
            )
        case .outfitsFilter:
            OutfitFilterView(
                filterModel: itemsSelectionDraft.outfitFilterModel,
                wardrobeType: "closet",
                selectedWardrobe: itemsSelectionDraft.selectedWardrobe
            )
        }
    }
    
    // MARK: - Days of Week Header
    private var daysOfWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                Text(String(day.prefix(3)))
                    .font(.caption)
                   // .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 25)
      //  .padding(.bottom, 8)
    }
    
    // MARK: - Change Month
    private func changeMonth(by value: Int) {
        withAnimation(.spring()) {
            currentMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) ?? currentMonth
        }
    }
    
    private static let maxVisibleEventLanes = 3
    private static let eventBarHeight: CGFloat = 13
    private static let eventBarSpacing: CGFloat = 2

    // MARK: - Calendar Grid
    private func calendarGrid(for month: Date, geo: GeometryProxy) -> some View {
        let weekdayHeaderHeight: CGFloat = 25
        let rows = 6
        let availableHeight = max(0, geo.size.height - weekdayHeaderHeight)
        let cellHeight = availableHeight / CGFloat(rows)
        let cellWidth = geo.size.width / 7
        let days = daysInMonth(month)

        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { weekIndex in
                let start = weekIndex * 7
                let weekDays = Array(days[start..<(start + 7)])
                weekRow(
                    weekDays: weekDays,
                    in: month,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight
                )
            }
        }
    }

    private func weekRow(
        weekDays: [Date],
        in displayedMonth: Date,
        cellWidth: CGFloat,
        cellHeight: CGFloat
    ) -> some View {
        let layout = eventLaneLayout(for: weekDays)
        let dayNumberHeight = cellWidth * 0.5
        let weekHasWardrobeSquare = weekDays.contains { gridWardrobeEvent(for: $0) != nil }
        let ootdSide = ootdSquareSide(
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            dayNumberHeight: dayNumberHeight,
            weekHasOotd: weekHasWardrobeSquare
        )
        // Day number, then event bars (week-aligned), then OOTD below bars in that cell.
        let eventsContentTop = dayNumberHeight + 2

        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.element) { dayIndex, date in
                    dayCell(
                        for: date,
                        in: displayedMonth,
                        width: cellWidth,
                        height: cellHeight,
                        ootdSide: ootdSide,
                        eventBarsHeight: eventBarsHeight(forDayIndex: dayIndex, layout: layout)
                    )
                }
            }

            if showsEventNamesOnGrid {
                spanningEventsOverlay(
                    layout: layout,
                    cellWidth: cellWidth,
                    eventsContentTop: eventsContentTop
                )
                .allowsHitTesting(false)
            }
        }
        .frame(height: cellHeight)
        .clipped()
    }

    /// Same OOTD size whether or not the cell also has event bars (bars push the square down; size does not shrink).
    private func ootdSquareSide(
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        dayNumberHeight: CGFloat,
        weekHasOotd: Bool
    ) -> CGFloat {
        guard weekHasOotd else { return 0 }
        let availableBelowNumber = max(0, cellHeight - dayNumberHeight - 2)
        return max(0, min(cellWidth, availableBelowNumber))
    }

    /// Vertical space taken by event bars (and +more) on a day so OOTD can sit underneath.
    private func eventBarsHeight(forDayIndex dayIndex: Int, layout: WeekEventLayout) -> CGFloat {
        let barStack = Self.eventBarHeight + Self.eventBarSpacing
        var maxLane = -1
        for segment in layout.segments where segment.startIndex <= dayIndex && dayIndex <= segment.endIndex {
            maxLane = max(maxLane, segment.lane)
        }
        let hasOverflow = layout.overflowByDay[dayIndex] > 0
        if hasOverflow {
            return CGFloat(Self.maxVisibleEventLanes) * barStack + Self.eventBarHeight
        }
        guard maxLane >= 0 else { return 0 }
        return CGFloat(maxLane + 1) * barStack
    }

    private func dayCell(
        for date: Date,
        in displayedMonth: Date,
        width: CGFloat,
        height: CGFloat,
        ootdSide: CGFloat,
        eventBarsHeight: CGFloat
    ) -> some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!)
        let isToday = calendar.isDateInToday(date)
        let ootdImage = gridWardrobeThumbnail(for: date)

        return VStack(spacing: 0) {
            dayNumberView(
                for: date,
                isToday: isToday,
                isSelected: isSelected,
                isCurrentMonth: isCurrentMonth,
                cellWidth: width
            )

            // Matches spanningEventsOverlay `eventsContentTop` (= dayNumberHeight + 2).
            Color.clear.frame(height: 2)

            if eventBarsHeight > 0 {
                Color.clear.frame(height: eventBarsHeight)
            }

            if let ootdImage, ootdSide > 8 {
                Image(uiImage: ootdImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ootdSide, height: ootdSide)
                    .clipped()
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)
        }
        .frame(width: width, height: height, alignment: .top)
        .contentShape(Rectangle())
        .overlay(Rectangle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
        .onTapGesture {
            selectedDate = date
            withAnimation(.easeInOut(duration: 0.3)) {
                showingEventDrawer = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(calendarWardrobeAccessibilityLabel(for: date, dayIsToday: isToday))
    }

    /// Wardrobe square for the grid — controlled by the eye-menu display mode.
    private func gridWardrobeEvent(for date: Date) -> Event? {
        let mode = calendarGridDisplayMode
        if mode.showsOOTDWardrobe, let ootd = outfitOfTheDayEvent(for: date) {
            return ootd
        }
        if mode.showsEventWardrobe {
            return nonOotdEventWardrobeEvent(for: date)
        }
        return nil
    }

    private func gridWardrobeThumbnail(for date: Date) -> UIImage? {
        guard let event = gridWardrobeEvent(for: date) else { return nil }
        if event.spansMultipleCalendarDays {
            return event.wardrobeThumbnailImage(for: date, in: viewContext)
        }
        if event.isTripLinkedDayOOTD, let parentId = event.tripParentEventId,
           let parent = events.first(where: { $0.id == parentId }) {
            return parent.wardrobeThumbnailImage(for: date, in: viewContext) ?? event.calendarThumbnailImage
        }
        return event.calendarThumbnailImage
    }

    /// Non-OOTD events with items/outfits on this day (includes multi-day trip parents with per-day wardrobe).
    private func nonOotdEventWardrobeEvent(for date: Date) -> Event? {
        let wardrobeEvents = events.filter { event in
            guard !event.isOutfitOfTheDay else { return false }
            guard eventOccupies(date, event: event) else { return false }
            if event.spansMultipleCalendarDays {
                return event.wardrobeThumbnailImage(for: date, in: viewContext) != nil
            }
            return EventTripDayWardrobe.hasWardrobeContent(event)
        }
        return wardrobeEvents.min { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
    }

    private func calendarWardrobeAccessibilityLabel(for date: Date, dayIsToday: Bool) -> String {
        let day = calendar.component(.day, from: date)
        let prefix = dayIsToday ? "Today, \(day)" : "\(day)"
        guard gridWardrobeEvent(for: date) != nil else { return prefix }
        if outfitOfTheDayEvent(for: date) != nil,
           calendarGridDisplayMode.showsOOTDWardrobe {
            return "\(prefix), Outfit of the Day"
        }
        return "\(prefix), Event outfit"
    }

    /// At most one standalone OOTD square per day — trip-linked day OOTDs belong to the parent event.
    /// Prefer a standalone OOTD for the day square; otherwise use a trip-linked day OOTD.
    private func outfitOfTheDayEvent(for date: Date) -> Event? {
        let ootds = events.filter { $0.isOutfitOfTheDay && eventOccupies(date, event: $0) }
        let standalone = ootds.filter { !$0.isTripLinkedDayOOTD }
        let preferred = standalone.isEmpty ? ootds : standalone
        return preferred.min { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
    }

    @ViewBuilder
    private func dayNumberView(
        for date: Date,
        isToday: Bool,
        isSelected: Bool,
        isCurrentMonth: Bool,
        cellWidth: CGFloat
    ) -> some View {
        ZStack {
            if isToday || isSelected {
                Circle()
                    .fill(isSelected ? Color.blue : Color.blue.opacity(0.2))
                    .frame(width: cellWidth * 0.5, height: cellWidth * 0.5)
            }

            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 14, weight: isToday ? .semibold : .regular))
                .foregroundColor(
                    isSelected ? .white :
                        (isToday ? .blue :
                            (isCurrentMonth ? .primary : .gray.opacity(0.5)))
                )
                .frame(width: cellWidth * 0.5, height: cellWidth * 0.5)
        }
    }

    private func spanningEventsOverlay(
        layout: WeekEventLayout,
        cellWidth: CGFloat,
        eventsContentTop: CGFloat
    ) -> some View {
        let y0 = eventsContentTop
        let barStack = Self.eventBarHeight + Self.eventBarSpacing

        return ZStack(alignment: .topLeading) {
            ForEach(layout.segments) { segment in
                // OOTD-only days must stay unlabeled (image square only) — never draw an empty bar.
                let title = segment.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    let x = CGFloat(segment.startIndex) * cellWidth + 1
                    let width = CGFloat(segment.endIndex - segment.startIndex + 1) * cellWidth - 2
                    let y = y0 + CGFloat(segment.lane) * barStack
                    Text(title)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .frame(width: width, height: Self.eventBarHeight, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.blue)
                        )
                        .offset(x: x, y: y)
                }
            }

            ForEach(0..<7, id: \.self) { dayIndex in
                let extra = layout.overflowByDay[dayIndex]
                if extra > 0 {
                    Text("+\(extra) more")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .frame(
                            width: cellWidth - 4,
                            height: Self.eventBarHeight,
                            alignment: .leading
                        )
                        .offset(
                            x: CGFloat(dayIndex) * cellWidth + 2,
                            y: y0 + CGFloat(Self.maxVisibleEventLanes) * barStack
                        )
                }
            }
        }
    }

    private func eventLaneLayout(for weekDays: [Date]) -> WeekEventLayout {
        guard showsEventNamesOnGrid else {
            return WeekEventLayout(segments: [], overflowByDay: Array(repeating: 0, count: 7))
        }
        let overlapping = events
            .filter { event in
                // OOTDs render as unlabeled image squares, never as titled bars.
                guard !event.isOutfitOfTheDay else { return false }
                // Draft / untitled rows would otherwise paint an empty blue bar across the cell.
                let title = (event.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return false }
                return weekDays.contains { eventOccupies($0, event: event) }
            }
            .sorted(by: eventLayoutSort)

        var laneDays: [[Bool]] = []
        var assignedLane: [NSManagedObjectID: Int] = [:]

        for event in overlapping {
            let mask = weekDays.map { eventOccupies($0, event: event) }
            var lane = 0
            while true {
                if lane == laneDays.count {
                    laneDays.append(Array(repeating: false, count: 7))
                }
                let conflict = zip(laneDays[lane], mask).contains { occupied, needed in occupied && needed }
                if !conflict {
                    for i in weekDays.indices where mask[i] {
                        laneDays[lane][i] = true
                    }
                    assignedLane[event.objectID] = lane
                    break
                }
                lane += 1
            }
        }

        var segments: [WeekEventSegment] = []
        var overflowByDay = Array(repeating: 0, count: 7)

        for event in overlapping {
            guard let lane = assignedLane[event.objectID] else { continue }
            let indices = weekDays.indices.filter { eventOccupies(weekDays[$0], event: event) }
            guard let first = indices.first, let last = indices.last else { continue }
            if lane < Self.maxVisibleEventLanes {
                segments.append(
                    WeekEventSegment(
                        id: "\(event.objectID.uriRepresentation().absoluteString)-\(first)-\(lane)",
                        title: event.name ?? "",
                        lane: lane,
                        startIndex: first,
                        endIndex: last
                    )
                )
            } else {
                for i in indices { overflowByDay[i] += 1 }
            }
        }

        return WeekEventLayout(segments: segments, overflowByDay: overflowByDay)
    }

    private func eventLayoutSort(_ lhs: Event, _ rhs: Event) -> Bool {
        let leftStart = calendar.startOfDay(for: lhs.startDate ?? .distantFuture)
        let rightStart = calendar.startOfDay(for: rhs.startDate ?? .distantFuture)
        if leftStart != rightStart { return leftStart < rightStart }
        let leftSpan = occupiedDayCount(lhs)
        let rightSpan = occupiedDayCount(rhs)
        if leftSpan != rightSpan { return leftSpan > rightSpan }
        return (lhs.name ?? "") < (rhs.name ?? "")
    }

    private func occupiedDayCount(_ event: Event) -> Int {
        guard let start = event.startDate else { return 0 }
        let end = event.endDate ?? start
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(1, days + 1)
    }

    /// Inclusive calendar-day occupancy (all-day end date included; timed events overlap any day they cover).
    private func eventOccupies(_ date: Date, event: Event) -> Bool {
        guard let start = event.startDate else { return false }
        let end = event.endDate ?? start
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }

        if isAllDayEvent(start: start, end: end) {
            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            return dayStart >= startDay && dayStart <= endDay
        }
        return start < dayEnd && end > dayStart
    }

    private func isAllDayEvent(start: Date, end: Date) -> Bool {
        let startParts = calendar.dateComponents([.hour, .minute], from: start)
        let endParts = calendar.dateComponents([.hour, .minute], from: end)
        return (startParts.hour == 0 && startParts.minute == 0)
            && (endParts.hour == 0 && endParts.minute == 0)
    }


    
    // MARK: - Helper Functions
    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
    
    private func daysInMonth(_ month: Date) -> [Date] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: month),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let paddingDays = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date] = []

        // Previous month fillers
        if paddingDays > 0 {
            for i in (1...paddingDays).reversed() {
                if let day = calendar.date(byAdding: .day, value: -i, to: firstOfMonth) {
                    days.append(day)
                }
            }
        }

        // Current month
        for day in monthRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }

        // Next month fillers to reach 42 cells
        let remainingCells = 42 - days.count
        if remainingCells > 0 {
            let lastDayOfMonth = days.last ?? firstOfMonth
            for i in 1...remainingCells {
                if let day = calendar.date(byAdding: .day, value: i, to: lastDayOfMonth) {
                    days.append(day)
                }
            }
        }


        return days
    }
    
    private func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    private func managedEvent(forURI uriString: String) -> Event? {
        guard let url = URL(string: uriString),
              let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let event = try? viewContext.existingObject(with: objectID) as? Event,
              event.isSoftDeleted != true else {
            return nil
        }
        return event
    }

    
    private func fetchEvents() {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.createdAt, ascending: false)]
        let notDeleted = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        if let uid = authSession.userId?.uuidString {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "userId == %@", uid),
                notDeleted,
            ])
        } else {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(value: false),
                notDeleted,
            ])
        }
        do {
            let results = try viewContext.fetch(request)
            DispatchQueue.main.async { self.events = results }
        } catch {
            print("Failed to fetch events: \(error)")
            DispatchQueue.main.async { self.events = [] }
        }
    }
}

private struct WeekEventSegment: Identifiable {
    let id: String
    let title: String
    let lane: Int
    let startIndex: Int
    let endIndex: Int
}

private struct WeekEventLayout {
    let segments: [WeekEventSegment]
    let overflowByDay: [Int]
}

// MARK: - Month Year Picker
struct MonthYearPicker: UIViewRepresentable {
    @Binding var selection: Date
    
    func makeUIView(context: Context) -> UIDatePicker {
        let datePicker = UIDatePicker()
        
        if #available(iOS 17.4, *) {
            datePicker.datePickerMode = .yearAndMonth
            datePicker.preferredDatePickerStyle = .wheels
        } else {
            datePicker.datePickerMode = .init(rawValue: 4269) ?? .date
            datePicker.preferredDatePickerStyle = .wheels
        }
        
        datePicker.date = selection
        datePicker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)
        
        return datePicker
    }
    
    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        uiView.date = selection
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MonthYearPicker
        
        init(_ parent: MonthYearPicker) {
            self.parent = parent
        }
        
        @objc func dateChanged(_ sender: UIDatePicker) {
            parent.selection = sender.date
        }
    }
}

