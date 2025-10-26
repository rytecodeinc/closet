//
//  OutfitCalendarView.swift
//  closet
//
//  Created by Dan Warner on 9/20/25.
//


import SwiftUI
import CoreData

struct OutfitCalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var events: [Event] = []

    @State private var selectedDate: Date? = nil
    @State private var showingEventDrawer = false
    @State private var showingCreateEvent = false
    
    @State private var currentMonth: Date = Date()
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
        
    private let calendar = Calendar.current
    
    var body: some View {
        NavigationView {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    
                    VStack(spacing: 0) {
                        Divider()
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
                    .padding(.top, 8)
                    .padding(.bottom, geo.safeAreaInsets.bottom)
                    .navigationTitle(monthYearString(for: currentMonth))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        // jump to today
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                let today = Date()
                                withAnimation(.spring()) {
                                    currentMonth = startOfMonth(for: today) // set month to today's month
                                    selectedDate = today                    // highlight today
                                }
                            }) {
                                Image(systemName: "calendar")
                            }
                        }
                        // create new event
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showingCreateEvent = true
                            }) {
                                Image(systemName: "plus")
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarLeading) {
                            
                            // Arrow navigation
                            HStack {
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
                            }
                        }
                    }
                    
                }
            }
        }
        .onAppear { fetchEvents() }
        .sheet(isPresented: $showingEventDrawer) {
            Group {
                if let selectedDate = selectedDate {
                    NavigationView {
                        EventDrawerView(
                            selectedDate: selectedDate,
                            onDismiss: {
                                showingEventDrawer = false
                                self.selectedDate = nil
                            },
                            onNavigateDate: { newDate in
                                self.selectedDate = newDate
                                self.currentMonth = startOfMonth(for: newDate)
                            }
                        )
                        .onDisappear {
                            fetchEvents()
                        }
                    }
                } else {
                    EmptyView()
                }
            }
            .presentationDetents([.medium, .large])
        }

        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView(initialDate: selectedDate ?? Date())
                .environment(\.managedObjectContext, viewContext)
                .onDisappear { fetchEvents() }
        }
    }
    
    // MARK: - Days of Week Header
    private var daysOfWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                Text(String(day.prefix(3)))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 30)
        .padding(.bottom, 8)
    }
    
    // MARK: - Change Month
    private func changeMonth(by value: Int) {
        withAnimation(.spring()) {
            currentMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) ?? currentMonth
        }
    }
    
    // MARK: - Calendar Grid
    private func calendarGrid(for month: Date, geo: GeometryProxy) -> some View {
        let weekdayHeaderHeight: CGFloat = 16
        let verticalPadding: CGFloat = 16 + 16
        let rows = 6
        let availableHeight = geo.size.height - weekdayHeaderHeight - verticalPadding - 0 // adjust for calendar day height
        let cellHeight = (availableHeight / CGFloat(rows)).rounded()
        
        let days = daysInMonth(month)
        let columns = Array(repeating: GridItem(.flexible(),  spacing: 0), count: 7)
        
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayCell(for: day, in: month, height: cellHeight)
            }
        }
    }
    
    private func dayCell(for date: Date, in displayedMonth: Date, height: CGFloat) -> some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let dayEvents = eventsForDate(date)
        let isSelected = selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!)
        let isToday = calendar.isDateInToday(date)
        let cellWidth = UIScreen.main.bounds.width / 7

        return VStack(spacing: 2) {
            dayNumberView(for: date, isToday: isToday, isSelected: isSelected, isCurrentMonth: isCurrentMonth, cellWidth: cellWidth)

            eventListView(for: dayEvents, cellWidth: cellWidth)

            Spacer(minLength: 2)
        }
        .frame(width: cellWidth, height: height)
        .contentShape(Rectangle())
        .overlay(Rectangle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
        .onTapGesture {
            selectedDate = date
            withAnimation(.easeInOut(duration: 0.3)) {
                showingEventDrawer = true
            }
        }
    }

    @ViewBuilder
    private func dayNumberView(for date: Date, isToday: Bool, isSelected: Bool, isCurrentMonth: Bool, cellWidth: CGFloat) -> some View {
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

    @ViewBuilder
    private func eventListView(for dayEvents: [Event], cellWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<min(dayEvents.count, 3), id: \.self) { index in
                if let eventName = dayEvents[index].name {
                    Text(eventName)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.blue)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if dayEvents.count > 3 {
                Text("+\(dayEvents.count - 3) more")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: cellWidth - 4, alignment: .leading)
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
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func eventsForDate(_ date: Date) -> [Event] {
        let dayStart = startOfDay(date)
        return events.filter {
            startOfDay($0.date ?? Date()) == dayStart
        }
    }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    
    private func fetchEvents() {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.timestamp, ascending: false)]
        do {
            let results = try viewContext.fetch(request)
            DispatchQueue.main.async { self.events = results }
        } catch {
            print("Failed to fetch events: \(error)")
            DispatchQueue.main.async { self.events = [] }
        }
    }
}









