//
//  PriceSelectionView.swift
//  closet
//
//  Created by Dan Warner on 8/3/25.
//


import SwiftUI
import CoreData

import SwiftUI

struct PriceSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var priceInput: String = ""
    @State private var selectedCurrency: String = Locale.current.currency?.identifier ?? "USD"
    @State private var isCurrencyPickerPresented = false

    private let allCurrencies: [String] = Locale.commonISOCurrencyCodes.sorted()

    var body: some View {
        VStack(spacing: 20) {
            SelectionHeader(title: "Set Price")

            HStack {
                // Currency button
                Button {
                    isCurrencyPickerPresented.toggle()
                } label: {
                    Text(currencySymbol(for: selectedCurrency))
                    //    .font(.title3.bold())
                        .frame(width: 55, height: 35)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Price input
                TextField("Enter price", text: $priceInput)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.leading)

                // Save button
                Button("Save") {
                    savePrice()
                }
                .disabled(!isValidDecimal)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .sheet(isPresented: $isCurrencyPickerPresented) {
            NavigationStack {
                List(allCurrencies, id: \.self) { code in
                    Button {
                        selectedCurrency = code
                        isCurrencyPickerPresented = false
                    } label: {
                        HStack {
                            Text(currencySymbol(for: code))
                                .frame(width: 50)
                            Text(code)
                            Spacer()
                            if code == selectedCurrency {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .navigationTitle("Select Currency")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            if let existingAmount = item.price?.amount as Decimal? {
                priceInput = NSDecimalNumber(decimal: existingAmount).stringValue
            }
            if let existingCurrency = item.price?.currency {
                selectedCurrency = existingCurrency
            }
        }
        .presentationDetents([.medium])
    }

    private var isValidDecimal: Bool {
        Decimal(string: priceInput) != nil
    }

    private func savePrice() {
        guard let decimalValue = Decimal(string: priceInput) else { return }

        // Always create a new Price object to ensure SwiftUI detects the change
        let newPrice = Price(context: viewContext)
        newPrice.amount = NSDecimalNumber(decimal: decimalValue)
        newPrice.currency = selectedCurrency  // ✅ store selected currency
        item.price = newPrice

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("❌ Failed to save price: \(error.localizedDescription)")
        }
    }

    private func currencySymbol(for code: String) -> String {
        let locale = Locale.availableIdentifiers
            .compactMap { Locale(identifier: $0) }
            .first { $0.currency?.identifier == code }
        return locale?.currencySymbol ?? code
    }
}



