//
//  PriceSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData
import UIKit

struct SetPriceView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var priceInput: String = ""
    @State private var selectedCurrency: String = Locale.current.currency?.identifier ?? "USD"
    @State private var isCurrencyPickerPresented = false

    private let allCurrencies: [String] = Locale.commonISOCurrencyCodes.sorted()

    var body: some View {
        VStack(spacing: 20) {
            SelectionPanelHeader(title: "Set Price")

            HStack {
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                    isCurrencyPickerPresented.toggle()
                } label: {
                    Text(CurrencyFormatting.symbol(forCurrencyCode: selectedCurrency))
                        .frame(width: 55, height: 35)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                PriceAmountTextField(text: $priceInput) {
                    finalizePriceInput()
                }
                .frame(height: 36)

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
                            Text(CurrencyFormatting.symbol(forCurrencyCode: code))
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
            if let existingAmount = item.price?.amount {
                priceInput = CurrencyFormatting.amountString(from: existingAmount)
            }
            if let existingCurrency = item.price?.currency {
                selectedCurrency = existingCurrency
            }
        }
        .presentationDetents([.height(150)])
    }

    private var isValidDecimal: Bool {
        CurrencyFormatting.parseAmount(priceInput) != nil
    }

    private func finalizePriceInput() {
        guard let finalized = CurrencyFormatting.finalizeAmountString(priceInput) else { return }
        priceInput = finalized
    }

    private func savePrice() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        finalizePriceInput()
        guard let decimalValue = CurrencyFormatting.parseAmount(priceInput) else { return }

        if let existingPrice = item.price {
            viewContext.delete(existingPrice)
        }

        let newPrice = Price(context: viewContext)
        newPrice.amount = NSDecimalNumber(decimal: decimalValue)
        newPrice.currency = selectedCurrency
        item.price = newPrice

        setUpdatedAt(item)

        if viewContext.parent == nil {
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save price: \(error.localizedDescription)")
            }
        }

        dismiss()
    }
}
