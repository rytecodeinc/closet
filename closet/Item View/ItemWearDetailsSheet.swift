//
//  ItemWearDetailsSheet.swift
//  closet
//
//  Calendar / wear-count sheet on owned item detail.
//

import SwiftUI
import CoreData

struct ItemWearDetailsSheet: View {
    @ObservedObject var item: Item

    private var wornEvents: [Event] {
        pastWornEvents(for: item)
    }

    private var lastWornEvent: Event? {
        wornEvents.first
    }

    private var firstWornEvent: Event? {
        wornEvents.last
    }

    private var wearsLast30Days: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return wornEvents.filter { event in
            guard let end = eventEffectiveEndDate(event) else { return false }
            return end >= cutoff
        }.count
    }

    private var wearsThisYear: Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        return wornEvents.filter { event in
            guard let end = eventEffectiveEndDate(event) else { return false }
            return calendar.component(.year, from: end) == year
        }.count
    }

    private var averageDaysBetweenWearsText: String? {
        guard wornEvents.count >= 2,
              let firstEvent = firstWornEvent,
              let lastEvent = lastWornEvent,
              let firstDate = eventEffectiveEndDate(firstEvent),
              let lastDate = eventEffectiveEndDate(lastEvent) else {
            return nil
        }

        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: firstDate)
        let lastDay = calendar.startOfDay(for: lastDate)
        let spanDays = calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0
        guard spanDays > 0 else { return nil }

        let rounded = max(1, Int((Double(spanDays) / Double(wornEvents.count - 1)).rounded()))
        return rounded == 1 ? "1 day" : "\(rounded) days"
    }

    private var costPerWearText: String? {
        guard let price = item.price, let amount = price.amount else { return nil }
        let wearCount = max(wornEvents.count, 1)
        let perWear = amount.dividing(by: NSDecimalNumber(value: wearCount))
        let code = price.currency ?? Locale.current.currency?.identifier ?? "USD"
        return CurrencyFormatting.displayPrice(amount: perWear, currencyCode: code)
    }

    private var purchasePriceText: String? {
        guard let price = item.price, let amount = price.amount else { return nil }
        let code = price.currency ?? Locale.current.currency?.identifier ?? "USD"
        return CurrencyFormatting.displayPrice(amount: amount, currencyCode: code)
    }

    private var purchaseDate: Date? {
        if let purchasedAt = item.purchasedAt { return purchasedAt }
        return item.createdAt ?? item.timestamp
    }

    private var showsThisYearWears: Bool {
        guard let purchaseDate else { return false }
        let calendar = Calendar.current
        let purchaseDay = calendar.startOfDay(for: purchaseDate)
        guard let oneYearLater = calendar.date(byAdding: .year, value: 1, to: purchaseDay) else {
            return false
        }
        return Date() >= oneYearLater
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SelectionHeader(title: "Wear Details")
                List {
                    Section {
                        statsRow(label: "Total Wears", value: wearCountValue(wornEvents.count))
                        statsRow(label: "Last 30 Days", value: wearCountValue(wearsLast30Days))
                        if showsThisYearWears {
                            statsRow(label: "This Year", value: wearCountValue(wearsThisYear))
                        }
                        if let costPerWearText {
                            statsRow(label: "Cost Per Wear", value: "\(costPerWearText) / wear")
                        }
                    }

                    Section {
                        if let purchaseDate {
                            datedWearRow(label: "Purchase Date", date: purchaseDate, eventName: nil, location: nil)
                        }

                        if let purchasePriceText {
                            statsRow(label: "Purchase Price", value: purchasePriceText)
                        }

                        if let averageDaysBetweenWearsText {
                            statsRow(label: "Average Days Between Wears", value: averageDaysBetweenWearsText)
                        }

                        if let event = lastWornEvent,
                           let date = eventEffectiveEndDate(event) {
                            datedWearRow(
                                label: "Last Worn",
                                date: date,
                                eventName: trimmedEventName(event),
                                location: wornEventHistoryLocationCaption(for: event)
                            )
                        }
                    }
                }
                .listStyle(.plain)
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(.systemBackground))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func wearCountValue(_ count: Int) -> String {
        count == 1 ? "1 wear" : "\(count) wears"
    }

    private func trimmedEventName(_ event: Event) -> String? {
        let name = event.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private func statsRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func datedWearRow(label: String, date: Date, eventName: String?, location: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let eventName {
                    Text(eventName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                Text(date, style: .date)
                    .foregroundStyle(.secondary)
                if let location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}
