//
//  UsernameChangePolicy.swift
//  closet
//
//  Users may change username at most once every 30 days.
//  See .cursor/rules/username-change-cooldown-deferred.mdc — revisit later.
//

import Foundation

enum UsernameChangePolicy {
    static let cooldownDays = 30

    /// `nil` last-changed means never locked (pre-migration / first change allowed).
    static func nextAllowedChangeDate(after lastChangedAt: Date?) -> Date? {
        guard let lastChangedAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: cooldownDays, to: lastChangedAt)
    }

    static func canChangeUsername(lastChangedAt: Date?, now: Date = .now) -> Bool {
        guard let next = nextAllowedChangeDate(after: lastChangedAt) else { return true }
        return now >= next
    }

    static var cooldownErrorMessage: String {
        "Username can only be changed once every \(cooldownDays) days"
    }

    static func lockedMessage(until date: Date) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        return "You can change your username again on \(formatted)."
    }
}
