//
//  CurrencyFormatting.swift
//  closet
//
//  Stable currency symbol + amount display for price UI.
//

import Foundation

enum CurrencyFormatting {
    /// Home locale for a currency so symbols stay local (e.g. USD → `$`, not `US$`).
    private static let homeLocaleIdentifiers: [String: String] = [
        "USD": "en_US",
        "CAD": "en_CA",
        "AUD": "en_AU",
        "NZD": "en_NZ",
        "GBP": "en_GB",
        "EUR": "de_DE",
        "JPY": "ja_JP",
        "CNY": "zh_CN",
        "KRW": "ko_KR",
        "INR": "en_IN",
        "MXN": "es_MX",
        "BRL": "pt_BR",
        "CHF": "de_CH",
        "SEK": "sv_SE",
        "NOK": "nb_NO",
        "DKK": "da_DK",
        "PLN": "pl_PL",
        "HKD": "zh_HK",
        "SGD": "en_SG",
        "TWD": "zh_TW",
        "THB": "th_TH",
        "PHP": "en_PH",
        "IDR": "id_ID",
        "MYR": "ms_MY",
        "VND": "vi_VN",
        "AED": "ar_AE",
        "SAR": "ar_SA",
        "ILS": "he_IL",
        "TRY": "tr_TR",
        "ZAR": "en_ZA",
        "RUB": "ru_RU",
    ]

    /// Symbol for an ISO currency code.
    /// 1) `Locale.current` when it already uses that currency
    /// 2) else that currency’s home locale (USD → en_US → `$`)
    /// 3) else a currency-only locale
    static func symbol(forCurrencyCode code: String) -> String {
        let trimmed = normalizedCurrencyCode(code)
        guard !trimmed.isEmpty else {
            return Locale.current.currencySymbol ?? "$"
        }

        if Locale.current.currency?.identifier.uppercased() == trimmed,
           let symbol = symbol(forCurrencyCode: trimmed, locale: .current) {
            return symbol
        }

        if let homeID = homeLocaleIdentifiers[trimmed],
           let symbol = symbol(forCurrencyCode: trimmed, locale: Locale(identifier: homeID)) {
            return symbol
        }

        let currencyOnly = Locale(
            identifier: Locale.identifier(
                fromComponents: [NSLocale.Key.currencyCode.rawValue: trimmed]
            )
        )
        if let symbol = symbol(forCurrencyCode: trimmed, locale: currencyOnly) {
            return symbol
        }

        return trimmed
    }

    /// Amount only: always 2 fraction digits (e.g. `18.00`).
    static func amountString(from amount: NSDecimalNumber) -> String {
        amountFormatter.string(from: amount) ?? "0.00"
    }

    static func amountString(from amount: Decimal) -> String {
        amountString(from: NSDecimalNumber(decimal: amount))
    }

    /// When editing ends / on save: parse and rewrite with 2 fraction digits.
    static func finalizeAmountString(_ raw: String) -> String? {
        guard let amount = parseAmount(raw) else { return nil }
        return amountString(from: amount)
    }

    /// Single display unit, e.g. `$18.00`.
    static func displayPrice(amount: NSDecimalNumber, currencyCode: String) -> String {
        "\(symbol(forCurrencyCode: currencyCode))\(amountString(from: amount))"
    }

    static func displayPrice(amount: Decimal, currencyCode: String) -> String {
        displayPrice(amount: NSDecimalNumber(decimal: amount), currencyCode: currencyCode)
    }

    /// Parses typed/saved price strings (`18`, `18.5`, `18.00`).
    static func parseAmount(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let groupingSeparator = Locale.current.groupingSeparator ?? ","
        var normalized = trimmed.replacingOccurrences(of: groupingSeparator, with: "")
        if normalized.hasSuffix(decimalSeparator) {
            normalized = String(normalized.dropLast())
        }
        guard !normalized.isEmpty else { return nil }

        if let number = amountFormatter.number(from: normalized) {
            return number.decimalValue
        }

        let dotted = normalized.replacingOccurrences(of: decimalSeparator, with: ".")
        return Decimal(string: dotted)
    }

    private static func normalizedCurrencyCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func symbol(forCurrencyCode code: String, locale: Locale) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let symbol = formatter.currencySymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let symbol, !symbol.isEmpty else { return nil }
        return symbol
    }

    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        return f
    }()
}
