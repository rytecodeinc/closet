//
//  PriceSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

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
            SelectionHeader(title: "Set Price")

            HStack {
                // Currency button
                Button {
                    isCurrencyPickerPresented.toggle()
                } label: {
                    Text(currencySymbol(for: selectedCurrency))
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

        // Delete existing price if any (to avoid orphaned Price objects)
        if let existingPrice = item.price {
            viewContext.delete(existingPrice)
        }

        // Create a new Price object
        let newPrice = Price(context: viewContext)
        newPrice.amount = NSDecimalNumber(decimal: decimalValue)
        newPrice.currency = selectedCurrency
        item.price = newPrice

        // Set updatedAt since we're modifying the item
        setUpdatedAt(item)

        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        // If viewContext has a parent, we're in a child context and shouldn't save
        if viewContext.parent == nil {
            // We're in a parent context (ItemDetailView), save immediately
            do {
                try viewContext.save()
                
                // Trigger automatic sync for the modified item
                SyncService.shared.syncItemIfNeeded(item)
            } catch {
                print("❌ Failed to save price: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
        
        dismiss()
    }

    private func currencySymbol(for code: String) -> String {
        let locale = Locale.availableIdentifiers
            .compactMap { Locale(identifier: $0) }
            .first { $0.currency?.identifier == code }
        return locale?.currencySymbol ?? code
    }
}
