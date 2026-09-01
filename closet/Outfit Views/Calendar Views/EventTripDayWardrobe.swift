//
//  EventTripDayWardrobe.swift
//  closet
//
//  Per-day Outfit of the Day rows linked to a multi-day all-day event.
//  Theme format: "ootd:<parentEventUUID>" (standalone OOTDs remain theme == "ootd").
//

import CoreData
import Foundation
import UIKit

enum EventTripDayWardrobe {

    /// Inclusive local calendar days from start through end.
    static func days(from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard startDay <= endDay else { return [startDay] }

        var days: [Date] = []
        var cursor = startDay
        while cursor <= endDay {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    static func themeMarker(parentEventId: UUID) -> String {
        "\(Event.ootdThemeMarker):\(parentEventId.uuidString.lowercased())"
    }

    /// Finds an existing day OOTD for this trip day, or creates a draft linked to the parent.
    @discardableResult
    static func dayOOTD(
        forParent parent: Event,
        day: Date,
        userId: String,
        in context: NSManagedObjectContext,
        createIfNeeded: Bool = true
    ) -> Event? {
        guard let parentId = parent.id else { return nil }
        let dayStart = Calendar.current.startOfDay(for: day)

        if let existing = findDayOOTD(parentEventId: parentId, day: dayStart, userId: userId, in: context) {
            return existing
        }
        guard createIfNeeded else { return nil }

        let ootd = Event(context: context)
        ootd.id = UUID()
        ootd.userId = userId
        ootd.name = Event.ootdDisplayName
        ootd.theme = themeMarker(parentEventId: parentId)
        ootd.eventVisibility = parent.eventVisibility
        ootd.startDate = dayStart
        ootd.endDate = dayStart
        ootd.date = dayStart
        ootd.timestamp = Date()
        ootd.isSoftDeleted = false
        setCreatedAndUpdatedAt(ootd)
        return ootd
    }

    static func findDayOOTD(
        parentEventId: UUID,
        day: Date,
        userId: String,
        in context: NSManagedObjectContext
    ) -> Event? {
        let dayStart = Calendar.current.startOfDay(for: day)
        let marker = themeMarker(parentEventId: parentEventId)
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "theme ==[c] %@", marker),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
            NSPredicate(format: "startDate >= %@ AND startDate < %@",
                        dayStart as NSDate,
                        Calendar.current.date(byAdding: .day, value: 1, to: dayStart)! as NSDate)
        ])
        return try? context.fetch(request).first
    }

    /// Soft-delete trip-linked OOTDs whose day falls outside the inclusive range.
    static func pruneDayOOTDs(
        forParent parent: Event,
        keepingDays days: [Date],
        userId: String,
        in context: NSManagedObjectContext
    ) {
        guard let parentId = parent.id else { return }
        let marker = themeMarker(parentEventId: parentId)
        let keep = Set(days.map { Calendar.current.startOfDay(for: $0).timeIntervalSince1970 })

        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "theme ==[c] %@", marker),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])
        guard let linked = try? context.fetch(request) else { return }

        for ootd in linked {
            let dayKey = Calendar.current.startOfDay(for: ootd.startDate ?? ootd.date ?? .distantPast)
                .timeIntervalSince1970
            if !keep.contains(dayKey) {
                softDelete(ootd)
            }
        }
    }

    /// All non-deleted trip-linked day OOTDs for a parent, sorted by calendar day.
    static func linkedDayOOTDs(
        forParent parent: Event,
        userId: String,
        in context: NSManagedObjectContext
    ) -> [Event] {
        guard let parentId = parent.id else { return [] }
        let marker = themeMarker(parentEventId: parentId)
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "theme ==[c] %@", marker),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])
        let linked = (try? context.fetch(request)) ?? []
        return linked.sorted {
            let left = Calendar.current.startOfDay(for: $0.startDate ?? $0.date ?? .distantPast)
            let right = Calendar.current.startOfDay(for: $1.startDate ?? $1.date ?? .distantPast)
            return left < right
        }
    }

    static func hasAnyDayWardrobeContent(
        forParent parent: Event,
        userId: String,
        in context: NSManagedObjectContext
    ) -> Bool {
        linkedDayOOTDs(forParent: parent, userId: userId, in: context)
            .contains { hasWardrobeContent($0) }
    }

    private static func assignDay(_ event: Event, to day: Date) {
        let dayStart = Calendar.current.startOfDay(for: day)
        event.startDate = dayStart
        event.endDate = dayStart
        event.date = dayStart
        setUpdatedAt(event)
    }

    private static func clearWardrobe(on event: Event) {
        if let existingItems = event.items as? NSOrderedSet {
            event.removeFromItems(existingItems)
        }
        if let existingOutfits = event.outfits as? Set<Outfit> {
            for outfit in existingOutfits {
                event.removeFromOutfits(outfit)
            }
        }
    }

    /// Moves items/outfits from `source` onto `target`, replacing target wardrobe.
    static func replaceWardrobe(on target: Event, withSource source: Event) {
        guard source.objectID != target.objectID else { return }
        clearWardrobe(on: target)

        let items: [Item] = {
            guard let ordered = source.items as? NSOrderedSet else { return [] }
            return ordered.array as? [Item] ?? []
        }()
        let outfits: [Outfit] = {
            guard let set = source.outfits as? Set<Outfit> else { return [] }
            return Array(set)
        }()

        clearWardrobe(on: source)
        for item in items {
            target.addToItems(item)
        }
        for outfit in outfits {
            target.addToOutfits(outfit)
        }
        setUpdatedAt(target)
        setUpdatedAt(source)
    }

    /// Shift day OOTDs by day index: oldDays[i] → newDays[i]. Extra old days are pruned.
    /// Collisions on a target day are replaced by the shifted source.
    static func shiftDayOOTDsByIndex(
        forParent parent: Event,
        fromDays oldDays: [Date],
        toDays newDays: [Date],
        userId: String,
        in context: NSManagedObjectContext
    ) {
        guard let parentId = parent.id, !oldDays.isEmpty else { return }
        let calendar = Calendar.current
        let pairCount = min(oldDays.count, newDays.count)

        var movers: [(Event, Date)] = []
        for index in 0..<pairCount {
            guard let ootd = findDayOOTD(
                parentEventId: parentId,
                day: oldDays[index],
                userId: userId,
                in: context
            ) else { continue }
            movers.append((ootd, calendar.startOfDay(for: newDays[index])))
        }

        let moverIDs = Set(movers.map { $0.0.objectID })
        let targetKeys = Set(movers.map { $0.1.timeIntervalSince1970 })

        // Soft-delete non-movers that sit on a target day (replace) or fall outside the new range.
        for ootd in linkedDayOOTDs(forParent: parent, userId: userId, in: context) {
            if moverIDs.contains(ootd.objectID) { continue }
            let ootdDay = calendar.startOfDay(for: ootd.startDate ?? ootd.date ?? .distantPast)
            let dayKey = ootdDay.timeIntervalSince1970
            let outsideNewRange = !newDays.contains { calendar.isDate($0, inSameDayAs: ootdDay) }
            if targetKeys.contains(dayKey) || outsideNewRange {
                softDelete(ootd)
            }
        }

        // Park movers on unique temporary days to avoid same-day collisions while reassigning.
        let parkBase = calendar.date(byAdding: .year, value: 100, to: Date()) ?? Date()
        for (offset, mover) in movers.enumerated() {
            if let park = calendar.date(byAdding: .day, value: offset, to: parkBase) {
                assignDay(mover.0, to: park)
            }
        }

        for (ootd, newDay) in movers {
            // Replace any leftover occupant on the destination.
            if let occupant = findDayOOTD(
                parentEventId: parentId,
                day: newDay,
                userId: userId,
                in: context
            ), occupant.objectID != ootd.objectID {
                softDelete(occupant)
            }
            assignDay(ootd, to: newDay)
        }

        pruneDayOOTDs(forParent: parent, keepingDays: newDays, userId: userId, in: context)
    }

    /// Multi-day → single-day: Day 1 wardrobe becomes the parent event wardrobe; prune all day OOTDs.
    static func foldFirstDayWardrobeOntoParent(
        parent: Event,
        fromDays oldDays: [Date],
        userId: String,
        in context: NSManagedObjectContext
    ) {
        guard let parentId = parent.id, let firstDay = oldDays.first else { return }
        if let day1 = findDayOOTD(parentEventId: parentId, day: firstDay, userId: userId, in: context),
           hasWardrobeContent(day1) {
            replaceWardrobe(on: parent, withSource: day1)
        } else {
            clearWardrobe(on: parent)
        }
        for ootd in linkedDayOOTDs(forParent: parent, userId: userId, in: context) {
            softDelete(ootd)
        }
    }

    /// Single-day → multi-day: parent wardrobe moves onto Day 1 OOTD; parent wardrobe cleared.
    @discardableResult
    static func promoteParentWardrobeToFirstDay(
        parent: Event,
        firstDay: Date,
        userId: String,
        in context: NSManagedObjectContext
    ) -> Event? {
        guard hasWardrobeContent(parent) else { return nil }
        guard let day1 = dayOOTD(
            forParent: parent,
            day: firstDay,
            userId: userId,
            in: context,
            createIfNeeded: true
        ) else { return nil }
        replaceWardrobe(on: day1, withSource: parent)
        return day1
    }

    /// Loose items linked directly to the event (not yet in an outfit).
    static func looseItems(on event: Event) -> [Item] {
        guard let ordered = event.items as? NSOrderedSet else { return [] }
        return ordered.array as? [Item] ?? []
    }

    /// Multiple loose items should prompt before auto-creating a closet outfit.
    static func shouldPromptSaveLooseItemsAsOutfit(on event: Event) -> Bool {
        looseItems(on: event).count > 1
    }

    /// Whether save should materialize loose items into a closet outfit.
    /// - Single loose item: never materialize — item stays on the event.
    /// - Multiple loose items: only when `saveMultipleAsOutfit == true`.
    static func shouldMaterializeLooseItemsOnSave(
        on event: Event,
        saveMultipleAsOutfit: Bool?
    ) -> Bool {
        let count = looseItems(on: event).count
        guard count > 1 else { return false }
        return saveMultipleAsOutfit == true
    }

    /// Same as OOTD save: turn loose items into a closet outfit (or reuse duplicate), clear items.
    @MainActor
    @discardableResult
    static func materializeLooseItemsIfNeeded(
        on event: Event,
        userId: String?,
        in context: NSManagedObjectContext
    ) -> Outfit? {
        let items: [Item] = {
            guard let ordered = event.items as? NSOrderedSet else { return [] }
            return ordered.array as? [Item] ?? []
        }()
        guard !items.isEmpty else { return nil }
        guard let uid = userId ?? event.userId, !uid.isEmpty else { return nil }

        guard let outfit = OutfitAutoGridMaterializer.matchingOrCreatingOutfit(
            from: items,
            userId: uid,
            in: context
        ) else { return nil }

        event.addToOutfits(outfit)
        if let existingItems = event.items as? NSOrderedSet {
            event.removeFromItems(existingItems)
        }
        return context.insertedObjects.contains(outfit) ? outfit : nil
    }

    static func thumbnails(for event: Event?) -> [EventSelectedThumbnail] {
        guard let event else { return [] }
        let outfits: [Outfit] = {
            guard let set = event.outfits as? Set<Outfit> else { return [] }
            return set.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }()
        let items: [Item] = {
            guard let ordered = event.items as? NSOrderedSet else { return [] }
            return ordered.array as? [Item] ?? []
        }()
        return outfits.map { .outfit($0) } + items.map { .item($0) }
    }

    static func hasWardrobeContent(_ event: Event?) -> Bool {
        !thumbnails(for: event).isEmpty
    }
}

extension Event {
    /// Theme value used for standalone OOTDs and as the prefix for trip-linked day OOTDs (`ootd:<uuid>`).
    static var ootdThemePrefix: String { ootdThemeMarker }

    var tripParentEventId: UUID? {
        let trimmed = (theme ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "\(Self.ootdThemeMarker):"
        guard trimmed.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let idString = String(trimmed.dropFirst(prefix.count))
        return UUID(uuidString: idString)
    }

    var isTripLinkedDayOOTD: Bool {
        tripParentEventId != nil
    }

    /// Multi-day all-day trip (midnight-to-midnight spanning more than one calendar day).
    var isMultiDayAllDayEvent: Bool {
        guard spansMultipleCalendarDays else { return false }
        guard let start = startDate, let end = endDate else { return false }
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        return (startComponents.hour == 0 && startComponents.minute == 0)
            && (endComponents.hour == 0 && endComponents.minute == 0)
    }

    /// Parent event spans more than one calendar day (all-day or timed).
    var spansMultipleCalendarDays: Bool {
        guard let start = startDate, let end = endDate else { return false }
        return !Calendar.current.isDate(start, inSameDayAs: end)
    }

    /// Thumbnail for a calendar day: trip day OOTD when this is a multi-day parent, else this event’s own.
    func wardrobeThumbnailImage(for day: Date, in context: NSManagedObjectContext) -> UIImage? {
        if isTripLinkedDayOOTD {
            return calendarThumbnailImage
        }
        guard spansMultipleCalendarDays,
              let parentId = id,
              let userId = userId,
              !userId.isEmpty else {
            return calendarThumbnailImage
        }
        if let dayOOTD = EventTripDayWardrobe.findDayOOTD(
            parentEventId: parentId,
            day: day,
            userId: userId,
            in: context
        ) {
            return dayOOTD.calendarThumbnailImage ?? calendarThumbnailImage
        }
        return calendarThumbnailImage
    }
}
